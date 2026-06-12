import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════
// ISO 15416 — 1D Barcode Analyzer
// ═══════════════════════════════════════════════════════
//
// Format detection strategy (in order):
//  1. NV21/YUV420: bytes.length >= W*H — first W*H bytes = pure luminance.
//     Most common Android camera format. isEstimated: false.
//  2. JPEG: bytes start with 0xFF 0xD8 — decode with image package.
//     Some devices/mobile_scanner versions return compressed JPEG.
//     isEstimated: false.
//  3. Conservative fallback: Grade C (not B). Grade C is the documented
//     minimum ML Kit requires to decode (~40% SC). Using B was wrong
//     because ML Kit reads at 15-20% SC (well below ISO Grade D).
//
// The ~est. badge in the UI signals which mode is in use.
// If ALL parameters show ~est. → device returns an unrecognized format.

class ISO15416Analyzer {
  ISOParameters analyze(BarcodeAnalysisInput input) {
    final decoded = input.rawValue != null;
    final profile = _extractScanProfile(input);
    if (profile != null) {
      return _analyzeFromProfile(profile, decoded, input);
    }
    return _conservativeFallback(decoded, input);
  }

  // ── Format detection & extraction ────────────────────────────────────────

  _ScanProfile? _extractScanProfile(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // Path 1: NV21 / YUV420 raw bytes — Y-plane = first W*H bytes
    if (bytes.length >= W * H) {
      return _profileFromYPlane(bytes, W, H, input);
    }

    // Path 2: JPEG (magic bytes FF D8)
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _profileFromJpeg(bytes, input);
    }

    return null;
  }

  // ── NV21 Y-plane path ────────────────────────────────────────────────────

  _ScanProfile? _profileFromYPlane(
      List<int> bytes, int W, int H, BarcodeAnalysisInput input) {
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
      x0 = 0; x1 = W;
      y0 = H ~/ 3; y1 = 2 * H ~/ 3;
    }
    final roiW = x1 - x0;
    if (roiW < 20 || y1 - y0 < 3) return null;

    int bestY = (y0 + y1) ~/ 2;
    int bestTransitions = 0;
    for (int y = y0; y < y1; y += 2) {
      final rowBase = y * W + x0;
      if (rowBase + roiW > bytes.length) break;
      int lo = 255, hi = 0;
      for (int x = 0; x < roiW; x++) {
        final v = bytes[rowBase + x];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (hi - lo < 38) continue;
      final thresh = (lo + hi) ~/ 2;
      int trans = 0;
      bool wasLight = bytes[rowBase] >= thresh;
      for (int x = 1; x < roiW; x++) {
        final isLight = bytes[rowBase + x] >= thresh;
        if (isLight != wasLight) { trans++; wasLight = isLight; }
      }
      if (trans > bestTransitions) { bestTransitions = trans; bestY = y; }
    }
    if (bestTransitions < 6) return null;

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
    if (rMax - rMin < 0.12) return null;

    return _ScanProfile(
      values: profile, rMax: rMax, rMin: rMin,
      edges: _detectEdges(profile, rMax, rMin),
    );
  }

  // ── JPEG path ────────────────────────────────────────────────────────────

  _ScanProfile? _profileFromJpeg(List<int> bytes, BarcodeAnalysisInput input) {
    final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (decoded == null) return null;

    final imgW = decoded.width;
    final imgH = decoded.height;
    final scaleX = imgW / (input.captureSize.width > 0 ? input.captureSize.width : imgW);
    final scaleY = imgH / (input.captureSize.height > 0 ? input.captureSize.height : imgH);

    final bb = input.boundingBox;
    int x0, x1, y0, y1;
    if (bb != null && bb.width > 10 && bb.height > 5) {
      final padX = (bb.width * scaleX * 0.3).toInt();
      final padY = (bb.height * scaleY * 0.5).toInt();
      x0 = ((bb.left * scaleX).toInt() - padX).clamp(0, imgW - 1);
      x1 = ((bb.right * scaleX).toInt() + padX).clamp(x0 + 1, imgW);
      y0 = ((bb.top * scaleY).toInt() - padY).clamp(0, imgH - 1);
      y1 = ((bb.bottom * scaleY).toInt() + padY).clamp(y0 + 1, imgH);
    } else {
      x0 = 0; x1 = imgW;
      y0 = imgH ~/ 3; y1 = 2 * imgH ~/ 3;
    }

    final roiW = x1 - x0;
    if (roiW < 20 || y1 - y0 < 3) return null;

    int bestY = (y0 + y1) ~/ 2;
    int bestTrans = 0;
    for (int y = y0; y < y1; y += 2) {
      int lo = 255, hi = 0;
      for (int x = x0; x < x1; x++) {
        final lv = _lum(decoded, x, y);
        if (lv < lo) lo = lv;
        if (lv > hi) hi = lv;
      }
      if (hi - lo < 38) continue;
      final thresh = (lo + hi) ~/ 2;
      int t = 0;
      bool wasLight = _lum(decoded, x0, y) >= thresh;
      for (int x = x0 + 1; x < x1; x++) {
        final isLight = _lum(decoded, x, y) >= thresh;
        if (isLight != wasLight) { t++; wasLight = isLight; }
      }
      if (t > bestTrans) { bestTrans = t; bestY = y; }
    }
    if (bestTrans < 6) return null;

    final profile = <double>[];
    for (int x = x0; x < x1; x++) {
      double sum = 0;
      int cnt = 0;
      for (int dy = -1; dy <= 1; dy++) {
        final y = bestY + dy;
        if (y >= y0 && y < y1) { sum += _lum(decoded, x, y) / 255.0; cnt++; }
      }
      profile.add(cnt > 0 ? sum / cnt : 0.5);
    }

    final rMax = profile.reduce(max);
    final rMin = profile.reduce(min);
    if (rMax - rMin < 0.12) return null;

    return _ScanProfile(
      values: profile, rMax: rMax, rMin: rMin,
      edges: _detectEdges(profile, rMax, rMin),
    );
  }

  int _lum(img.Image image, int x, int y) {
    final p = image.getPixel(
      x.clamp(0, image.width - 1), y.clamp(0, image.height - 1));
    return (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
  }

  // ── ISO calculations from profile ────────────────────────────────────────

  ISOParameters _analyzeFromProfile(
      _ScanProfile p, bool decoded, BarcodeAnalysisInput input) {
    final sc = _calcSC(p);
    final mr = _calcMR(p);
    final ec = _calcEC(p);
    final mod = _calcMOD(p, sc.rawMeasurement / 100.0, ec.rawMeasurement);
    final def = _calcDEF(p, sc.rawMeasurement / 100.0);
    return ISOParameters(
      symbolContrast: sc,
      minimumReflectance: mr,
      edgeContrast: ec,
      modulation: mod,
      defects: def,
      decodability: _calcDecodability(decoded),
      quietZones: _calcQuietZones(input),
    );
  }

  GradeValue _calcSC(_ScanProfile p) {
    final pct = (p.rMax - p.rMin) * 100.0;
    ISOGrade g;
    if (pct >= 70) g = ISOGrade.A;
    else if (pct >= 55) g = ISOGrade.B;
    else if (pct >= 40) g = ISOGrade.C;
    else if (pct >= 20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcMR(_ScanProfile p) {
    final ok = p.rMin <= 0.5 * p.rMax;
    final g = ok ? ISOGrade.A : ISOGrade.F;
    return GradeValue(rawMeasurement: p.rMin * 100, unit: '%', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcEC(_ScanProfile p) {
    if (p.edges.isEmpty) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F, numericGrade: 0);
    }
    final minEC = p.edges.map((e) => e.contrast).reduce(min);
    ISOGrade g;
    if (minEC >= 0.15) g = ISOGrade.A;
    else if (minEC >= 0.12) g = ISOGrade.B;
    else if (minEC >= 0.10) g = ISOGrade.C;
    else if (minEC >= 0.07) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: minEC, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcMOD(_ScanProfile p, double sc, double ecMin) {
    final mod = sc > 0 ? (ecMin / sc).clamp(0.0, 1.0) : 0.0;
    ISOGrade g;
    if (mod >= 0.70) g = ISOGrade.A;
    else if (mod >= 0.60) g = ISOGrade.B;
    else if (mod >= 0.50) g = ISOGrade.C;
    else if (mod >= 0.40) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcDEF(_ScanProfile p, double sc) {
    if (p.edges.length < 2) {
      return GradeValue(rawMeasurement: 0.05, unit: 'ratio', grade: ISOGrade.A, numericGrade: 4.0);
    }
    double maxERN = 0;
    for (int i = 1; i < p.values.length - 1; i++) {
      final e = (p.values[i] - p.values[i - 1]).abs();
      if (e > maxERN) maxERN = e;
    }
    final def = sc > 0 ? (maxERN / sc).clamp(0.0, 1.0) : 1.0;
    ISOGrade g;
    if (def <= 0.15) g = ISOGrade.A;
    else if (def <= 0.20) g = ISOGrade.B;
    else if (def <= 0.25) g = ISOGrade.C;
    else if (def <= 0.30) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  List<_Edge> _detectEdges(List<double> profile, double rMax, double rMin) {
    final threshold = rMin + (rMax - rMin) * 0.5;
    final edges = <_Edge>[];
    bool wasAbove = profile[0] > threshold;
    for (int i = 1; i < profile.length; i++) {
      final isAbove = profile[i] > threshold;
      if (isAbove != wasAbove) {
        final t = (threshold - profile[i - 1]) / (profile[i] - profile[i - 1]);
        edges.add(_Edge(
          position: (i - 1) + t,
          contrast: (profile[i] - profile[i - 1]).abs(),
          toLight: isAbove,
        ));
        wasAbove = isAbove;
      }
    }
    return edges;
  }

  GradeValue _calcDecodability(bool decoded) {
    final g = decoded ? ISOGrade.A : ISOGrade.F;
    return GradeValue(
      rawMeasurement: decoded ? 1.0 : 0.0, unit: 'bool',
      grade: g, numericGrade: g.numeric,
    );
  }

  GradeValue _calcQuietZones(BarcodeAnalysisInput input) {
    final bb = input.boundingBox;
    if (bb == null || input.captureSize.width == 0) {
      return GradeValue(
        rawMeasurement: 5.0, unit: 'X', grade: ISOGrade.C, numericGrade: 2.0,
        isEstimated: true, estimationBasis: 'Sin datos de posición del símbolo',
      );
    }
    final leftQZ = bb.left;
    final rightQZ = input.captureSize.width - bb.right;
    final minQZ = leftQZ < rightQZ ? leftQZ : rightQZ;
    final modW = bb.width > 0 ? bb.width / _expectedModuleCount(input.symbology) : 1.0;
    final qzMods = modW > 0 ? minQZ / modW : 0.0;
    final req = _requiredQuietZone(input.symbology);
    ISOGrade g;
    if (qzMods >= req) g = ISOGrade.A;
    else if (qzMods >= req * 0.8) g = ISOGrade.B;
    else if (qzMods >= req * 0.6) g = ISOGrade.C;
    else if (qzMods >= req * 0.4) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: qzMods, unit: 'X', grade: g, numericGrade: g.numeric);
  }

  // ── Conservative fallback — no usable image ───────────────────────────────
  // Grade C = minimum ML Kit requires. NEVER Grade B.
  // (ML Kit decodes at ~15% SC which is ISO Grade F)

  ISOParameters _conservativeFallback(bool decoded, BarcodeAnalysisInput input) {
    final g = decoded ? ISOGrade.C : ISOGrade.F;
    const basis = 'Estimación — formato de imagen no reconocido o sin imagen';
    GradeValue est(double raw, String unit) => GradeValue(
      rawMeasurement: raw, unit: unit, grade: g, numericGrade: g.numeric,
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

class ISO15415Analyzer {
  ISOParameters analyze(BarcodeAnalysisInput input) {
    final decoded = input.rawValue != null;
    final corners = input.corners;

    final dec = _calcDecodability(decoded);
    final gnu = _calcGNU(corners);
    final anu = _calcANU(corners);
    final fpd = _calcFPD(corners);
    final uec = _calcUEC(input.rawValue, input.symbology);

    final metrics = _extract2DMetrics(input);
    final sc = metrics != null ? _calcSCFromMetrics(metrics) : _est(decoded, 40.0, 10.0, '%');
    final mod = metrics != null ? _calcMODFromMetrics(metrics) : _est(decoded, 0.25, 0.0, 'ratio');
    final def = metrics != null ? _calcDEFFromMetrics(metrics) : _est(decoded, 0.25, 0.90, 'ratio');
    final pg = metrics != null ? _calcPGFromMetrics(metrics) : _est(decoded, 5.0, 15.0, '%');

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

  // ── Metrics extraction (NV21 or JPEG) ────────────────────────────────────

  _2DMetrics? _extract2DMetrics(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    if (bytes.length >= W * H) return _metricsFromYPlane(bytes, W, H, input);
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _metricsFromJpeg(bytes, input);
    }
    return null;
  }

  _2DMetrics? _metricsFromYPlane(
      List<int> bytes, int W, int H, BarcodeAnalysisInput input) {
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

    double rMin = 1.0, rMax = 0.0, sum = 0.0, sumSq = 0.0;
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
        sum += lum; sumSq += lum * lum; count++;
      }
    }
    if (count == 0 || rMax - rMin < 0.10) return null;
    final mean = sum / count;
    final variance = (sumSq / count) - mean * mean;
    return _2DMetrics(rMax: rMax, rMin: rMin, mean: mean,
        stdDev: variance > 0 ? sqrt(variance) : 0.0);
  }

  _2DMetrics? _metricsFromJpeg(List<int> bytes, BarcodeAnalysisInput input) {
    final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (decoded == null) return null;

    final imgW = decoded.width;
    final imgH = decoded.height;
    final scaleX = imgW / (input.captureSize.width > 0 ? input.captureSize.width : imgW);
    final scaleY = imgH / (input.captureSize.height > 0 ? input.captureSize.height : imgH);

    final bb = input.boundingBox;
    int x0, x1, y0, y1;
    if (bb != null && bb.width > 10 && bb.height > 10) {
      x0 = (bb.left * scaleX).toInt().clamp(0, imgW - 1);
      x1 = (bb.right * scaleX).toInt().clamp(x0 + 1, imgW);
      y0 = (bb.top * scaleY).toInt().clamp(0, imgH - 1);
      y1 = (bb.bottom * scaleY).toInt().clamp(y0 + 1, imgH);
    } else {
      x0 = imgW ~/ 4; x1 = 3 * imgW ~/ 4;
      y0 = imgH ~/ 4; y1 = 3 * imgH ~/ 4;
    }

    double rMin = 1.0, rMax = 0.0, sum = 0.0, sumSq = 0.0;
    int count = 0;
    const step = 4;
    for (int y = y0; y < y1; y += step) {
      for (int x = x0; x < x1; x += step) {
        final p = decoded.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        if (lum < rMin) rMin = lum;
        if (lum > rMax) rMax = lum;
        sum += lum; sumSq += lum * lum; count++;
      }
    }
    if (count == 0 || rMax - rMin < 0.10) return null;
    final mean = sum / count;
    final variance = (sumSq / count) - mean * mean;
    return _2DMetrics(rMax: rMax, rMin: rMin, mean: mean,
        stdDev: variance > 0 ? sqrt(variance) : 0.0);
  }

  // ── Photometric from metrics ──────────────────────────────────────────────

  GradeValue _calcSCFromMetrics(_2DMetrics m) {
    final pct = (m.rMax - m.rMin) * 100.0;
    ISOGrade g;
    if (pct >= 70) g = ISOGrade.A;
    else if (pct >= 55) g = ISOGrade.B;
    else if (pct >= 40) g = ISOGrade.C;
    else if (pct >= 20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcMODFromMetrics(_2DMetrics m) {
    final range = m.rMax - m.rMin;
    final mod = range > 0 ? ((m.stdDev / range) * 2).clamp(0.0, 1.0) : 0.0;
    ISOGrade g;
    if (mod >= 0.35) g = ISOGrade.A;
    else if (mod >= 0.30) g = ISOGrade.B;
    else if (mod >= 0.25) g = ISOGrade.C;
    else if (mod >= 0.20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcDEFFromMetrics(_2DMetrics m) {
    final range = m.rMax - m.rMin;
    final expectedMean = (m.rMin + m.rMax) / 2;
    final def = range > 0
        ? ((m.mean - expectedMean).abs() / range * 0.6).clamp(0.0, 1.0)
        : 1.0;
    ISOGrade g;
    if (def <= 0.15) g = ISOGrade.A;
    else if (def <= 0.20) g = ISOGrade.B;
    else if (def <= 0.25) g = ISOGrade.C;
    else if (def <= 0.30) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcPGFromMetrics(_2DMetrics m) {
    final pg = ((m.mean - 0.5).abs() * 20.0).clamp(0.0, 15.0);
    ISOGrade g;
    if (pg <= 2.0) g = ISOGrade.A;
    else if (pg <= 3.5) g = ISOGrade.B;
    else if (pg <= 5.0) g = ISOGrade.C;
    else if (pg <= 7.0) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pg, unit: '%', grade: g, numericGrade: g.numeric);
  }

  // ── Geometric params ──────────────────────────────────────────────────────

  GradeValue _calcDecodability(bool decoded) {
    final g = decoded ? ISOGrade.A : ISOGrade.F;
    return GradeValue(rawMeasurement: decoded ? 1.0 : 0.0, unit: 'bool',
        grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcGNU(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.05, unit: 'X', grade: ISOGrade.A,
          numericGrade: 4.0, isEstimated: true,
          estimationBasis: 'Sin corners disponibles');
    }
    final top = _dist(corners[0], corners[1]);
    final bottom = _dist(corners[3], corners[2]);
    final avg = (top + bottom) / 2;
    final gnu = avg > 0 ? (top - bottom).abs() / avg : 0.0;
    ISOGrade g;
    if (gnu <= 0.06) g = ISOGrade.A;
    else if (gnu <= 0.08) g = ISOGrade.B;
    else if (gnu <= 0.10) g = ISOGrade.C;
    else if (gnu <= 0.13) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: gnu, unit: 'X', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcANU(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.04, unit: 'ratio', grade: ISOGrade.A,
          numericGrade: 4.0, isEstimated: true,
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
    ISOGrade g;
    if (anu <= 0.06) g = ISOGrade.A;
    else if (anu <= 0.08) g = ISOGrade.B;
    else if (anu <= 0.10) g = ISOGrade.C;
    else if (anu <= 0.14) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: anu, unit: 'ratio', grade: g, numericGrade: g.numeric);
  }

  GradeValue _calcFPD(List<Offset>? corners) {
    if (corners == null || corners.length < 4) {
      return GradeValue(rawMeasurement: 0.0, unit: 'ratio', grade: ISOGrade.B,
          numericGrade: 3.0, isEstimated: true,
          estimationBasis: 'Estimado desde geometría de corners');
    }
    final sides = [
      _dist(corners[0], corners[1]), _dist(corners[3], corners[2]),
      _dist(corners[0], corners[3]), _dist(corners[1], corners[2]),
    ];
    final avg = sides.reduce((a, b) => a + b) / 4;
    final maxDev = avg > 0
        ? sides.map((s) => (s - avg).abs() / avg).reduce((a, b) => a > b ? a : b)
        : 0.0;
    ISOGrade g;
    if (maxDev <= 0.10) g = ISOGrade.A;
    else if (maxDev <= 0.15) g = ISOGrade.B;
    else if (maxDev <= 0.20) g = ISOGrade.C;
    else if (maxDev <= 0.25) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: maxDev, unit: 'ratio', grade: g,
        numericGrade: g.numeric, isEstimated: true,
        estimationBasis: 'Regularidad geométrica de corners');
  }

  GradeValue _calcUEC(String? rawValue, BarcodeType symbology) {
    if (rawValue == null) {
      return GradeValue(rawMeasurement: 0.0, unit: '%', grade: ISOGrade.F,
          numericGrade: 0.0, isEstimated: true,
          estimationBasis: 'No decodificado');
    }
    final pct = (symbology == BarcodeType.pdf417) ? 50.0 : 62.0;
    final g = pct >= 62 ? ISOGrade.A : ISOGrade.B;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: g,
        numericGrade: g.numeric, isEstimated: true,
        estimationBasis: 'ECC interno no accesible via ML Kit');
  }

  GradeValue _est(bool decoded, double goodVal, double badVal, String unit) {
    final g = decoded ? ISOGrade.C : ISOGrade.F;
    return GradeValue(
      rawMeasurement: decoded ? goodVal : badVal, unit: unit,
      grade: g, numericGrade: g.numeric, isEstimated: true,
      estimationBasis: decoded
          ? 'Estimación conservadora — imagen no analizable'
          : 'No decodificado',
    );
  }

  double _dist(Offset a, Offset b) {
    final dx = a.dx - b.dx; final dy = a.dy - b.dy;
    return sqrt(dx * dx + dy * dy);
  }
}

class _2DMetrics {
  final double rMax, rMin, mean, stdDev;
  _2DMetrics({required this.rMax, required this.rMin,
      required this.mean, required this.stdDev});
}
