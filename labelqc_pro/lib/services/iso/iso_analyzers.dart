import 'dart:math';
import 'dart:ui';
import '../../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════
// ISO 15416 — 1D Barcode Analyzer
// ═══════════════════════════════════════════════════════
//
// Strategy (priority order):
//  1. Extract Y-plane from NV21/YUV420 bytes (Android camera, always available
//     when returnImage:true). NV21 = first W*H bytes = pure luminance.
//     → real ISO measurement, isEstimated: false
//  2. Conservative geometric fallback (no image at all)
//     → Grade C (the documented ML Kit minimum), isEstimated: true
//
// The previous bug: "decoded → Grade B" was wrong because ML Kit reads
// barcodes far below ISO Grade C quality. We now measure the actual pixels.

class ISO15416Analyzer {
  ISOParameters analyze(BarcodeAnalysisInput input) {
    final decoded = input.rawValue != null;

    // Try real pixel analysis from Y-plane (NV21/YUV420)
    final profile = _extractYPlaneProfile(input);
    if (profile != null) {
      return _analyzeFromProfile(profile, decoded, input);
    }

    // Conservative fallback — no image available
    return _conservativeFallback(decoded, input);
  }

  // ── Y-plane extraction ────────────────────────────────────────────────────

  _ScanProfile? _extractYPlaneProfile(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // NV21 (Android default): total = W*H*3/2, first W*H bytes = Y plane
    if (bytes.length < W * H) return null;

    // Region of interest: barcode area + padding
    final bb = input.boundingBox;
    int x0, x1, y0, y1;
    if (bb != null && bb.width > 10 && bb.height > 5) {
      final padX = (bb.width * 0.4).toInt();
      final padY = (bb.height * 0.6).toInt();
      x0 = (bb.left.toInt() - padX).clamp(0, W - 1);
      x1 = (bb.right.toInt() + padX).clamp(x0 + 1, W);
      y0 = (bb.top.toInt() - padY).clamp(0, H - 1);
      y1 = (bb.bottom.toInt() + padY).clamp(y0 + 1, H);
    } else {
      // No position data — scan middle third of frame
      x0 = 0; x1 = W;
      y0 = H ~/ 3; y1 = 2 * H ~/ 3;
    }

    final roiW = x1 - x0;
    if (roiW < 20 || y1 - y0 < 3) return null;

    // Find the row with the most light/dark transitions (= barcode scanline)
    int bestY = (y0 + y1) ~/ 2;
    int bestTransitions = 0;

    for (int y = y0; y < y1; y += 2) {
      final rowBase = y * W + x0;
      if (rowBase + roiW > bytes.length) break;

      // Quick contrast check
      int lo = 255, hi = 0;
      for (int x = 0; x < roiW; x++) {
        final v = bytes[rowBase + x];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (hi - lo < 38) continue; // < 15% contrast → not a barcode row

      final thresh = (lo + hi) ~/ 2;
      int transitions = 0;
      bool wasLight = bytes[rowBase] >= thresh;
      for (int x = 1; x < roiW; x++) {
        final isLight = bytes[rowBase + x] >= thresh;
        if (isLight != wasLight) { transitions++; wasLight = isLight; }
      }
      if (transitions > bestTransitions) {
        bestTransitions = transitions;
        bestY = y;
      }
    }

    // Need at least 6 transitions for a real barcode
    if (bestTransitions < 6) return null;

    // Average 3 rows around bestY for robustness
    final profile = List<double>.filled(roiW, 0.0);
    int rowCount = 0;
    for (int dy = -1; dy <= 1; dy++) {
      final y = bestY + dy;
      if (y < 0 || y >= H) continue;
      final base = y * W + x0;
      if (base + roiW > bytes.length) continue;
      for (int x = 0; x < roiW; x++) profile[x] += bytes[base + x] / 255.0;
      rowCount++;
    }
    if (rowCount == 0) return null;
    for (int x = 0; x < roiW; x++) profile[x] /= rowCount;

    final rMax = profile.reduce(max);
    final rMin = profile.reduce(min);
    if (rMax - rMin < 0.12) return null; // not enough contrast

    return _ScanProfile(
      values: profile,
      rMax: rMax,
      rMin: rMin,
      edges: _detectEdges(profile, rMax, rMin),
    );
  }

  // ── Real ISO analysis from scan profile ───────────────────────────────────

  ISOParameters _analyzeFromProfile(
      _ScanProfile p, bool decoded, BarcodeAnalysisInput input) {
    final sc = _calcSC(p);
    final mr = _calcMR(p);
    final ec = _calcEC(p);
    final mod = _calcMOD(p, sc.rawMeasurement / 100.0, ec.rawMeasurement);
    final def = _calcDEF(p, sc.rawMeasurement / 100.0);
    final dec = _calcDecodability(decoded);
    final qz = _calcQuietZones(input);

    return ISOParameters(
      symbolContrast: sc,
      minimumReflectance: mr,
      edgeContrast: ec,
      modulation: mod,
      defects: def,
      decodability: dec,
      quietZones: qz,
    );
  }

  GradeValue _calcSC(_ScanProfile p) {
    final pct = (p.rMax - p.rMin) * 100.0;
    ISOGrade grade;
    if (pct >= 70) grade = ISOGrade.A;
    else if (pct >= 55) grade = ISOGrade.B;
    else if (pct >= 40) grade = ISOGrade.C;
    else if (pct >= 20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcMR(_ScanProfile p) {
    final passes = p.rMin <= 0.5 * p.rMax;
    final grade = passes ? ISOGrade.A : ISOGrade.F;
    return GradeValue(rawMeasurement: p.rMin * 100.0, unit: '%',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcEC(_ScanProfile p) {
    if (p.edges.isEmpty) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio',
          grade: ISOGrade.F, numericGrade: 0, isEstimated: false);
    }
    final minEC = p.edges.map((e) => e.contrast).reduce(min);
    ISOGrade grade;
    if (minEC >= 0.15) grade = ISOGrade.A;
    else if (minEC >= 0.12) grade = ISOGrade.B;
    else if (minEC >= 0.10) grade = ISOGrade.C;
    else if (minEC >= 0.07) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: minEC, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcMOD(_ScanProfile p, double sc, double ecMin) {
    final mod = sc > 0 ? (ecMin / sc).clamp(0.0, 1.0) : 0.0;
    ISOGrade grade;
    if (mod >= 0.70) grade = ISOGrade.A;
    else if (mod >= 0.60) grade = ISOGrade.B;
    else if (mod >= 0.50) grade = ISOGrade.C;
    else if (mod >= 0.40) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcDEF(_ScanProfile p, double sc) {
    if (p.edges.length < 2) {
      return GradeValue(rawMeasurement: 0.05, unit: 'ratio',
          grade: ISOGrade.A, numericGrade: 4.0, isEstimated: false);
    }
    double maxERN = 0;
    final vals = p.values;
    for (int i = 1; i < vals.length - 1; i++) {
      final ern = (vals[i] - vals[i - 1]).abs();
      if (ern > maxERN) maxERN = ern;
    }
    final def = sc > 0 ? (maxERN / sc).clamp(0.0, 1.0) : 1.0;
    ISOGrade grade;
    if (def <= 0.15) grade = ISOGrade.A;
    else if (def <= 0.20) grade = ISOGrade.B;
    else if (def <= 0.25) grade = ISOGrade.C;
    else if (def <= 0.30) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  List<_Edge> _detectEdges(List<double> profile, double rMax, double rMin) {
    final threshold = rMin + (rMax - rMin) * 0.5;
    final edges = <_Edge>[];
    bool wasAbove = profile[0] > threshold;
    for (int i = 1; i < profile.length; i++) {
      final isAbove = profile[i] > threshold;
      if (isAbove != wasAbove) {
        final t = (threshold - profile[i - 1]) / (profile[i] - profile[i - 1]);
        final pos = (i - 1) + t;
        edges.add(_Edge(
          position: pos,
          contrast: (profile[i] - profile[i - 1]).abs(),
          toLight: isAbove,
        ));
        wasAbove = isAbove;
      }
    }
    return edges;
  }

  // ── Exact geometric params ────────────────────────────────────────────────

  GradeValue _calcDecodability(bool decoded) {
    final grade = decoded ? ISOGrade.A : ISOGrade.F;
    return GradeValue(
      rawMeasurement: decoded ? 1.0 : 0.0, unit: 'bool',
      grade: grade, numericGrade: grade.numeric, isEstimated: false,
    );
  }

  GradeValue _calcQuietZones(BarcodeAnalysisInput input) {
    final bb = input.boundingBox;
    if (bb == null || input.captureSize.width == 0) {
      return GradeValue(
        rawMeasurement: 5.0, unit: 'X',
        grade: ISOGrade.C, numericGrade: 2.0,
        isEstimated: true,
        estimationBasis: 'Sin datos de posición del símbolo',
      );
    }
    final leftQZ = bb.left;
    final rightQZ = input.captureSize.width - bb.right;
    final minQZ = leftQZ < rightQZ ? leftQZ : rightQZ;
    final moduleWidth = bb.width > 0
        ? bb.width / _expectedModuleCount(input.symbology) : 1.0;
    final qzModules = moduleWidth > 0 ? minQZ / moduleWidth : 0.0;
    final required = _requiredQuietZone(input.symbology);
    ISOGrade grade;
    if (qzModules >= required) grade = ISOGrade.A;
    else if (qzModules >= required * 0.8) grade = ISOGrade.B;
    else if (qzModules >= required * 0.6) grade = ISOGrade.C;
    else if (qzModules >= required * 0.4) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: qzModules, unit: 'X',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  // ── Conservative fallback (no image) ─────────────────────────────────────
  // Grade C = documented minimum that ML Kit requires (~40% SC).
  // NOT Grade B — ML Kit can read barcodes worse than Grade C.

  ISOParameters _conservativeFallback(bool decoded, BarcodeAnalysisInput input) {
    final grade = decoded ? ISOGrade.C : ISOGrade.F;
    final basis = decoded
        ? 'Estimación conservadora — imagen no disponible para análisis real'
        : 'No decodificado';
    GradeValue est(double raw, String unit) => GradeValue(
      rawMeasurement: raw, unit: unit,
      grade: grade, numericGrade: grade.numeric,
      isEstimated: true, estimationBasis: basis,
    );
    return ISOParameters(
      symbolContrast: est(decoded ? 40.0 : 10.0, '%'),
      minimumReflectance: est(decoded ? 30.0 : 80.0, '%'),
      edgeContrast: est(decoded ? 0.10 : 0.02, 'ratio'),
      modulation: est(decoded ? 0.50 : 0.05, 'ratio'),
      defects: est(decoded ? 0.25 : 0.90, 'ratio'),
      decodability: _calcDecodability(decoded),
      quietZones: _calcQuietZones(input),
    );
  }

  double _expectedModuleCount(BarcodeType t) {
    switch (t) {
      case BarcodeType.ean13: return 95.0;
      case BarcodeType.ean8: return 67.0;
      case BarcodeType.upcA: return 95.0;
      case BarcodeType.upcE: return 51.0;
      case BarcodeType.code128: return 35.0;
      case BarcodeType.code39: return 30.0;
      case BarcodeType.itf: return 20.0;
      default: return 30.0;
    }
  }

  double _requiredQuietZone(BarcodeType t) {
    switch (t) {
      case BarcodeType.code128:
      case BarcodeType.gs1_128: return 10.0;
      case BarcodeType.ean13:
      case BarcodeType.ean8: return 7.0;
      case BarcodeType.upcA:
      case BarcodeType.upcE: return 9.0;
      default: return 10.0;
    }
  }
}

class _ScanProfile {
  final List<double> values;
  final double rMax, rMin;
  final List<_Edge> edges;
  _ScanProfile({required this.values, required this.rMax,
      required this.rMin, required this.edges});
}

class _Edge {
  final double position, contrast;
  final bool toLight;
  _Edge({required this.position, required this.contrast, required this.toLight});
}

// ═══════════════════════════════════════════════════════
// ISO 15415 — 2D Barcode Analyzer
// ═══════════════════════════════════════════════════════
//
// Same strategy as ISO15416:
//  1. Y-plane from NV21 → real photometric analysis of the 2D patch
//  2. GNU / ANU from corners → exact geometry
//  3. Conservative fallback when no image

class ISO15415Analyzer {
  ISOParameters analyze(BarcodeAnalysisInput input) {
    final decoded = input.rawValue != null;
    final corners = input.corners;

    // Exact geometric params (independent of image)
    final dec = _calcDecodability(decoded);
    final gnu = _calcGNU(corners);
    final anu = _calcANU(corners);
    final fpd = _calcFPD(corners);

    // Photometric params: try Y-plane, else conservative estimate
    final metrics = _extract2DMetrics(input);
    final sc = metrics != null ? _calcSCFromMetrics(metrics) : _estimatedSC(decoded);
    final mod = metrics != null ? _calcMODFromMetrics(metrics) : _estimatedMOD(decoded);
    final def = metrics != null ? _calcDEFFromMetrics(metrics) : _estimatedDEF(decoded);
    final uec = _calcUEC(input.rawValue, input.symbology);
    final pg = metrics != null ? _calcPGFromMetrics(metrics) : _estimatedPG(decoded);

    return ISOParameters(
      symbolContrast: sc,
      modulation: mod,
      defects: def,
      decodability: dec,
      fixedPatternDamage: fpd,
      gridNonuniformity: gnu,
      axialNonuniformity: anu,
      unusedErrorCorrection: uec,
      printGrowth: pg,
    );
  }

  // ── Y-plane 2D metrics ────────────────────────────────────────────────────

  _2DMetrics? _extract2DMetrics(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0 || bytes.length < W * H) return null;

    // Crop to barcode region
    final bb = input.boundingBox;
    int x0, x1, y0, y1;
    if (bb != null && bb.width > 10 && bb.height > 10) {
      x0 = bb.left.toInt().clamp(0, W - 1);
      x1 = bb.right.toInt().clamp(x0 + 1, W);
      y0 = bb.top.toInt().clamp(0, H - 1);
      y1 = bb.bottom.toInt().clamp(y0 + 1, H);
    } else {
      x0 = W ~/ 4; x1 = 3 * W ~/ 4;
      y0 = H ~/ 4; y1 = 3 * H ~/ 4;
    }

    if (x1 - x0 < 10 || y1 - y0 < 10) return null;

    double rMin = 1.0, rMax = 0.0, sum = 0.0;
    double sumSq = 0.0;
    int count = 0;
    const step = 3;

    for (int y = y0; y < y1; y += step) {
      final rowBase = y * W;
      for (int x = x0; x < x1; x += step) {
        final idx = rowBase + x;
        if (idx >= bytes.length) continue;
        final lum = bytes[idx] / 255.0;
        if (lum < rMin) rMin = lum;
        if (lum > rMax) rMax = lum;
        sum += lum;
        sumSq += lum * lum;
        count++;
      }
    }

    if (count == 0 || rMax - rMin < 0.10) return null;

    final mean = sum / count;
    final variance = (sumSq / count) - mean * mean;
    final stdDev = variance > 0 ? sqrt(variance) : 0.0;

    return _2DMetrics(rMax: rMax, rMin: rMin, mean: mean, stdDev: stdDev);
  }

  // ── Photometric params from 2D metrics ────────────────────────────────────

  GradeValue _calcSCFromMetrics(_2DMetrics m) {
    final pct = (m.rMax - m.rMin) * 100.0;
    ISOGrade grade;
    if (pct >= 70) grade = ISOGrade.A;
    else if (pct >= 55) grade = ISOGrade.B;
    else if (pct >= 40) grade = ISOGrade.C;
    else if (pct >= 20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcMODFromMetrics(_2DMetrics m) {
    // Bimodality: how well are dark/light modules separated relative to range
    final range = m.rMax - m.rMin;
    final normalizedStd = range > 0 ? m.stdDev / range : 0.0;
    // For a perfect bimodal distribution, std ≈ 0.5 * range → normalizedStd ≈ 0.5
    // Poor modulation → std closer to 0 (everything similar brightness)
    final mod = (normalizedStd * 2).clamp(0.0, 1.0);
    ISOGrade grade;
    if (mod >= 0.35) grade = ISOGrade.A;
    else if (mod >= 0.30) grade = ISOGrade.B;
    else if (mod >= 0.25) grade = ISOGrade.C;
    else if (mod >= 0.20) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcDEFFromMetrics(_2DMetrics m) {
    // Defects: anomalous reflectance as fraction of SC
    final range = m.rMax - m.rMin;
    // Mean should be near (rMin + rMax) / 2 for a healthy 2D code
    final expectedMean = (m.rMin + m.rMax) / 2;
    final deviation = (m.mean - expectedMean).abs() / (range > 0 ? range : 1);
    final def = (deviation * 0.6).clamp(0.0, 1.0);
    ISOGrade grade;
    if (def <= 0.15) grade = ISOGrade.A;
    else if (def <= 0.20) grade = ISOGrade.B;
    else if (def <= 0.25) grade = ISOGrade.C;
    else if (def <= 0.30) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcPGFromMetrics(_2DMetrics m) {
    // Print Growth proxy: how far the mean is from 50% reflectance
    // A perfect code has mean near 0.5 (equal dark/light area)
    final pg = ((m.mean - 0.5).abs() * 20.0).clamp(0.0, 15.0);
    ISOGrade grade;
    if (pg <= 2.0) grade = ISOGrade.A;
    else if (pg <= 3.5) grade = ISOGrade.B;
    else if (pg <= 5.0) grade = ISOGrade.C;
    else if (pg <= 7.0) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: pg, unit: '%',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  // ── Exact geometric params ────────────────────────────────────────────────

  GradeValue _calcDecodability(bool decoded) {
    final grade = decoded ? ISOGrade.A : ISOGrade.F;
    return GradeValue(
      rawMeasurement: decoded ? 1.0 : 0.0, unit: 'bool',
      grade: grade, numericGrade: grade.numeric, isEstimated: false,
    );
  }

  GradeValue _calcGNU(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.05, unit: 'X',
          grade: ISOGrade.A, numericGrade: 4.0,
          isEstimated: true,
          estimationBasis: 'Sin corners disponibles');
    }
    final top = _dist(corners[0], corners[1]);
    final bottom = _dist(corners[3], corners[2]);
    final avg = (top + bottom) / 2;
    final gnu = avg > 0 ? (top - bottom).abs() / avg : 0.0;
    ISOGrade grade;
    if (gnu <= 0.06) grade = ISOGrade.A;
    else if (gnu <= 0.08) grade = ISOGrade.B;
    else if (gnu <= 0.10) grade = ISOGrade.C;
    else if (gnu <= 0.13) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: gnu, unit: 'X',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcANU(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.04, unit: 'ratio',
          grade: ISOGrade.A, numericGrade: 4.0,
          isEstimated: true,
          estimationBasis: 'Sin corners disponibles');
    }
    final top = _dist(corners[0], corners[1]);
    final bottom = _dist(corners[3], corners[2]);
    final left = _dist(corners[0], corners[3]);
    final right = _dist(corners[1], corners[2]);
    final avgH = (top + bottom) / 2;
    final avgV = (left + right) / 2;
    final anu = (avgH + avgV) > 0
        ? (avgH - avgV).abs() / ((avgH + avgV) / 2) : 0.0;
    ISOGrade grade;
    if (anu <= 0.06) grade = ISOGrade.A;
    else if (anu <= 0.08) grade = ISOGrade.B;
    else if (anu <= 0.10) grade = ISOGrade.C;
    else if (anu <= 0.14) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: anu, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric, isEstimated: false);
  }

  GradeValue _calcFPD(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.0, unit: 'ratio',
          grade: ISOGrade.B, numericGrade: 3.0,
          isEstimated: true,
          estimationBasis: 'Sin corners — inferido desde decodificación');
    }
    final sides = [
      _dist(corners[0], corners[1]),
      _dist(corners[3], corners[2]),
      _dist(corners[0], corners[3]),
      _dist(corners[1], corners[2]),
    ];
    final avg = sides.reduce((a, b) => a + b) / 4;
    final maxDev = avg > 0
        ? sides.map((s) => (s - avg).abs() / avg).reduce((a, b) => a > b ? a : b)
        : 0.0;
    ISOGrade grade;
    if (maxDev <= 0.10) grade = ISOGrade.A;
    else if (maxDev <= 0.15) grade = ISOGrade.B;
    else if (maxDev <= 0.20) grade = ISOGrade.C;
    else if (maxDev <= 0.25) grade = ISOGrade.D;
    else grade = ISOGrade.F;
    return GradeValue(rawMeasurement: maxDev, unit: 'ratio',
        grade: grade, numericGrade: grade.numeric,
        isEstimated: true,
        estimationBasis: 'Estimado desde regularidad geométrica de corners');
  }

  GradeValue _calcUEC(String? rawValue, BarcodeType symbology) {
    if (rawValue == null) {
      return GradeValue(rawMeasurement: 0.0, unit: '%',
          grade: ISOGrade.F, numericGrade: 0.0,
          isEstimated: true, estimationBasis: 'No decodificado');
    }
    final uecPct = (symbology == BarcodeType.pdf417) ? 50.0 : 62.0;
    ISOGrade grade;
    if (uecPct >= 62) grade = ISOGrade.A;
    else if (uecPct >= 50) grade = ISOGrade.B;
    else grade = ISOGrade.C;
    return GradeValue(rawMeasurement: uecPct, unit: '%',
        grade: grade, numericGrade: grade.numeric,
        isEstimated: true,
        estimationBasis: 'Estimado — acceso al ECC interno no disponible');
  }

  // ── Conservative estimated params (no image) ─────────────────────────────

  GradeValue _estimatedSC(bool decoded) => GradeValue(
    rawMeasurement: decoded ? 40.0 : 10.0, unit: '%',
    grade: decoded ? ISOGrade.C : ISOGrade.F,
    numericGrade: decoded ? 2.0 : 0.0,
    isEstimated: true,
    estimationBasis: decoded
        ? 'Estimación conservadora — imagen no disponible'
        : 'No decodificado',
  );

  GradeValue _estimatedMOD(bool decoded) => GradeValue(
    rawMeasurement: decoded ? 0.25 : 0.0, unit: 'ratio',
    grade: decoded ? ISOGrade.C : ISOGrade.F,
    numericGrade: decoded ? 2.0 : 0.0,
    isEstimated: true,
    estimationBasis: decoded
        ? 'Estimación conservadora — imagen no disponible'
        : 'No decodificado',
  );

  GradeValue _estimatedDEF(bool decoded) => GradeValue(
    rawMeasurement: decoded ? 0.25 : 0.90, unit: 'ratio',
    grade: decoded ? ISOGrade.C : ISOGrade.F,
    numericGrade: decoded ? 2.0 : 0.0,
    isEstimated: true,
    estimationBasis: decoded
        ? 'Estimación conservadora — imagen no disponible'
        : 'No decodificado',
  );

  GradeValue _estimatedPG(bool decoded) => GradeValue(
    rawMeasurement: decoded ? 5.0 : 15.0, unit: '%',
    grade: decoded ? ISOGrade.C : ISOGrade.F,
    numericGrade: decoded ? 2.0 : 0.0,
    isEstimated: true,
    estimationBasis: decoded
        ? 'Estimación conservadora — imagen no disponible'
        : 'No decodificado',
  );

  double _dist(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return sqrt(dx * dx + dy * dy);
  }
}

class _2DMetrics {
  final double rMax, rMin, mean, stdDev;
  _2DMetrics(
      {required this.rMax, required this.rMin,
       required this.mean, required this.stdDev});
}
