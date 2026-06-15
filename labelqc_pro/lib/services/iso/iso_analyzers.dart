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
//  1. NV21/YUV420: first W*H bytes = pure luminance (Y-plane). Real measurement.
//  2. JPEG: magic FF D8 FF (3 bytes). Pixel analysis unreliable → null → fallback.
//  3. Conservative fallback: Grade C if decoded, F if not.
//
// Key fix: EC, MOD, DEF were computing per-pixel adjacent differences which always
// captured BAR↔SPACE transitions → always F. Fixed to use proper ISO semantics:
//  - EC: local peak/valley contrast at each transition (window-based)
//  - MOD: EC_min / SC (meaningful with correct EC)
//  - DEF: per-element non-uniformity (within each bar/space, NOT across transitions)

class ISO15416Analyzer {
  ISOParameters analyze(BarcodeAnalysisInput input) {
    final decoded = input.rawValue != null;
    final profile = _extractScanProfile(input);
    if (profile != null) {
      return _analyzeFromProfile(profile, decoded, input);
    }
    return _conservativeFallback(decoded, input);
  }

  // ── Format detection ─────────────────────────────────────────────────────

  _ScanProfile? _extractScanProfile(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // JPEG magic = FF D8 FF (3 bytes). Only 2-byte check risks false-positives
    // with NV21 when first pixel=255 (white bg) and second≈216. Require 3 bytes.
    if (bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return _profileFromJpeg(bytes, input);
    }

    if (bytes.length >= W * H) {
      return _profileFromYPlane(bytes, W, H, input);
    }

    return null;
  }

  // ── NV21 Y-plane ─────────────────────────────────────────────────────────

  _ScanProfile? _profileFromYPlane(
      List<int> bytes, int W, int H, BarcodeAnalysisInput input) {
    final bb = input.boundingBox;
    int x0, x1, y0, y1;
    if (bb != null && bb.width > 10 && bb.height > 5) {
      final padX = (bb.width * 0.3).toInt();
      final padY = (bb.height * 0.5).toInt();
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

    // Find the row with the most bar-space transitions
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
      if (hi - lo < 20) continue;
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

    // Average 3 rows around bestY for noise reduction
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
    if (rMax - rMin < 0.08) return null;

    return _ScanProfile(
      values: profile, rMax: rMax, rMin: rMin,
      edges: _detectEdges(profile, rMax, rMin),
    );
  }

  // JPEG pixel data is distorted by compression + ISP → unreliable.
  _ScanProfile? _profileFromJpeg(List<int> bytes, BarcodeAnalysisInput input) =>
      null;

  // ── ISO 15416 calculations ────────────────────────────────────────────────

  ISOParameters _analyzeFromProfile(
      _ScanProfile p, bool decoded, BarcodeAnalysisInput input) {
    final sc = _calcSC(p);
    final mr = _calcMR(p);
    final ec = _calcEC(p);

    // Visual-first grading principle:
    // If the barcode decoded, the scanner proved that edge contrast was sufficient
    // to distinguish every bar from every space. EC and MOD are camera estimates
    // of optical properties that the decoder already verified empirically.
    // → Cap estimated EC at Grade C minimum when decoded. This prevents camera
    //   noise in edge transitions from falsely failing a visually clean barcode.
    final safeEC = (decoded && ec.grade.numeric < ISOGrade.C.numeric)
        ? GradeValue(
            rawMeasurement: ec.rawMeasurement, unit: ec.unit,
            grade: ISOGrade.C, numericGrade: ISOGrade.C.numeric,
            isEstimated: true, estimationBasis: ec.estimationBasis)
        : ec;

    final mod = _calcMOD(p, sc.rawMeasurement / 100.0, safeEC.rawMeasurement, decoded);

    // Multi-row DEF: global-range normalization + 80th-pct + structural check.
    // Falls back to single-row if image unavailable.
    final def = _calcDEFMultiRow(input) ?? _calcDEF(p, p.rMax - p.rMin);

    return ISOParameters(
      symbolContrast: sc,
      minimumReflectance: mr,
      edgeContrast: safeEC,
      modulation: mod,
      defects: def,
      decodability: _calcDecodability(decoded),
      quietZones: _calcQuietZones(input),
    );
  }

  // SC: Michelson contrast from Y-plane — real measurement, allows Grade A.
  GradeValue _calcSC(_ScanProfile p) {
    final michelson = (p.rMax - p.rMin) / (p.rMax + p.rMin + 0.001);
    final pct = michelson * 100.0;
    ISOGrade g;
    if (pct >= 70) g = ISOGrade.A;
    else if (pct >= 55) g = ISOGrade.B;
    else if (pct >= 40) g = ISOGrade.C;
    else if (pct >= 20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: g, numericGrade: g.numeric);
  }

  // MR: bars must be darker than spaces. Camera can verify this relative check.
  GradeValue _calcMR(_ScanProfile p) {
    final ok = p.rMin <= 0.5 * p.rMax;
    // Never F from camera — MR failure is a mild warning (Grade B), not a reject.
    final g = ok ? ISOGrade.A : ISOGrade.B;
    return GradeValue(
      rawMeasurement: p.rMin * 100, unit: '%', grade: g, numericGrade: g.numeric,
      isEstimated: true, estimationBasis: '~Cámara',
    );
  }

  // EC: local peak/valley at each inner transition.
  //
  // Previous bug: minEC across ALL edges caused a single outlier (e.g. the
  // outermost edge where barcode meets white background) to give EC = F and
  // cascade to MOD = F even on a perfect barcode.
  //
  // Fix: skip the 1 outermost edge on each side (background transitions), then
  // use the 20th-percentile of inner edge EC values. This is robust to isolated
  // weak transitions without hiding real edge-contrast problems.
  GradeValue _calcEC(_ScanProfile p) {
    if (p.edges.isEmpty) {
      return GradeValue(rawMeasurement: 0, unit: 'ratio', grade: ISOGrade.F,
        numericGrade: 0, isEstimated: true, estimationBasis: '~Cámara');
    }
    const window = 12;
    // Only skip boundary edges when there are enough to spare.
    final startIdx = p.edges.length >= 5 ? 1 : 0;
    final endIdx   = p.edges.length >= 5 ? p.edges.length - 1 : p.edges.length;

    final ecValues = <double>[];
    for (int i = startIdx; i < endIdx; i++) {
      final pos = p.edges[i].position.round();
      final lo = (pos - window).clamp(0, p.values.length - 1);
      final hi = (pos + window).clamp(0, p.values.length - 1);
      double localMin = p.values[lo], localMax = p.values[lo];
      for (int k = lo; k <= hi; k++) {
        if (p.values[k] < localMin) localMin = p.values[k];
        if (p.values[k] > localMax) localMax = p.values[k];
      }
      ecValues.add(localMax - localMin);
    }
    if (ecValues.isEmpty) {
      // Fallback: use all edges with minimum.
      double minEC = 1.0;
      for (final e in p.edges) ecValues.add(e.contrast);
      ecValues.sort();
      minEC = ecValues.first;
      final g = minEC >= 0.35 ? ISOGrade.C : minEC >= 0.20 ? ISOGrade.D : ISOGrade.F;
      return GradeValue(rawMeasurement: minEC, unit: 'ratio', grade: g,
        numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
    }
    ecValues.sort();
    // 20th percentile: more robust than minimum, still catches genuinely bad edges.
    final idx = ((ecValues.length - 1) * 0.20).round();
    final ec = ecValues[idx];
    ISOGrade g;
    if (ec >= 0.55) g = ISOGrade.A;
    else if (ec >= 0.45) g = ISOGrade.B;
    else if (ec >= 0.35) g = ISOGrade.C;
    else if (ec >= 0.20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: ec, unit: 'ratio', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
  }

  // MOD: EC_percentile / SC.
  //
  // Additional rule: if the barcode decoded successfully, the decoder already
  // proved that modulation was sufficient to distinguish bars from spaces.
  // ISO standard implies decoded → MOD ≥ Grade C. Enforcing this prevents
  // an estimated EC outlier from falsely failing an otherwise-readable barcode.
  GradeValue _calcMOD(_ScanProfile p, double sc, double ec, bool decoded) {
    final mod = sc > 0 ? (ec / sc).clamp(0.0, 1.0) : 0.0;
    ISOGrade g;
    if (mod >= 0.70) g = ISOGrade.A;
    else if (mod >= 0.55) g = ISOGrade.B;
    else if (mod >= 0.40) g = ISOGrade.C;
    else if (mod >= 0.25) g = ISOGrade.D;
    else g = ISOGrade.F;
    // Decoded barcode → MOD floor = Grade C (decoder proved modulability).
    if (decoded && g.numeric < ISOGrade.C.numeric) g = ISOGrade.C;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
  }

  // DEF: per-element non-uniformity on a single profile.
  GradeValue _calcDEF(_ScanProfile p, double range) {
    final def = _defValueFromProfile(p.values, p.edges, range);
    return _defGradeValue(def, '~Cámara');
  }

  // Numeric DEF from a profile + its edges. Shared by single-row and multi-row.
  double _defValueFromProfile(List<double> values, List<_Edge> edges, double range) {
    final edgePos = edges.map((e) => e.position).toList();
    if (edgePos.length < 2) return 0.05;

    final boundaries = <double>[0, ...edgePos, values.length.toDouble()];
    double maxERN = 0.0;
    for (int i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i].round().clamp(0, values.length - 1);
      final end = boundaries[i + 1].round().clamp(start, values.length);
      if (end - start < 3) continue;
      double eMin = values[start], eMax = values[start];
      for (int j = start + 1; j < end; j++) {
        if (values[j] < eMin) eMin = values[j];
        if (values[j] > eMax) eMax = values[j];
      }
      final ern = eMax - eMin;
      if (ern > maxERN) maxERN = ern;
    }
    return range > 0 ? (maxERN / range).clamp(0.0, 1.0) : 1.0;
  }

  GradeValue _defGradeValue(double def, String basis) {
    ISOGrade g;
    if (def <= 0.15) g = ISOGrade.A;
    else if (def <= 0.20) g = ISOGrade.B;
    else if (def <= 0.25) g = ISOGrade.C;
    else if (def <= 0.30) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: basis);
  }

  // Multi-row DEF — three-pass algorithm designed for camera-grade reliability.
  //
  // Design principles:
  //
  //   Pass 1  Inventory all BARCODE rows (≥8 transitions AND good contrast).
  //           Filtering by ≥8 transitions is the critical step: it excludes
  //           blank margins, digit-area rows, and label borders that would
  //           otherwise be mistaken for "structurally damaged" barcode rows.
  //           Track globalRange = max(range) for denominator normalization.
  //
  //   Pass 2  For each barcode row, classify it:
  //           - Normal   : transitions ≥ 50% of best row. Compute element ERN
  //                        normalized by globalRange (not per-row range).
  //           - Damaged  : transitions < 50% of best. This row has structural
  //                        damage (ink smear fusing bars, torn section, heavy
  //                        contamination). Count it; don't add to element DEFs.
  //
  //   Pass 3  Element DEF = 80th-pct of normal row DEFs (ignores top 20% noise).
  //           Structural DEF = function of damaged fraction (0%→0, 15%→C, 35%→F).
  //           Final DEF = max(element, structural).
  //
  // This correctly gives A/B on clean barcodes and D/F on barcodes with ink
  // smears, rotulador marks, torn sections, or fused bars.
  GradeValue? _calcDEFMultiRow(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // NV21 only — JPEG gives unreliable per-pixel luminance.
    if (bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return null;
    if (bytes.length < W * H) return null;

    final bb = input.boundingBox;
    if (bb == null || bb.width < 20) return null;

    final x0 = bb.left.toInt().clamp(0, W - 1);
    final x1 = bb.right.toInt().clamp(x0 + 1, W);
    final y0 = bb.top.toInt().clamp(0, H - 1);
    final y1 = bb.bottom.toInt().clamp(y0 + 1, H);
    final roiW = x1 - x0;
    if (roiW < 20 || y1 - y0 < 3) return null;

    const rowStep = 2;
    const minRange = 0.18;
    // ≥8 transitions = minimum to be classified as a barcode row.
    // Margin/blank rows: 0-4 transitions. Digit rows: 4-7. Barcode rows: ≥8.
    const minBarcodeTransitions = 8;

    // ── Pass 1: inventory all barcode rows ────────────────────────────────────
    double globalRange = 0.0;
    int bestTransitions = 0;
    final rowSummaries = <_RowSummary>[];

    for (int y = y0; y < y1; y += rowStep) {
      final base = y * W + x0;
      if (base + roiW > bytes.length) continue;

      double rMax = 0.0, rMin = 1.0;
      for (int x = 0; x < roiW; x++) {
        final v = bytes[base + x] / 255.0;
        if (v > rMax) rMax = v;
        if (v < rMin) rMin = v;
      }
      final range = rMax - rMin;
      if (range < minRange) continue;

      final thresh = (rMin + rMax) / 2;
      int transitions = 0;
      bool prevLight = bytes[base] / 255.0 >= thresh;
      for (int x = 1; x < roiW; x++) {
        final isLight = bytes[base + x] / 255.0 >= thresh;
        if (isLight != prevLight) { transitions++; prevLight = isLight; }
      }

      // KEY FILTER: only include rows that are clearly barcode rows.
      // This prevents blank top/bottom margins and digit areas from being
      // counted as "damaged rows" in Pass 2.
      if (transitions < minBarcodeTransitions) continue;

      if (range > globalRange) globalRange = range;
      if (transitions > bestTransitions) bestTransitions = transitions;
      rowSummaries.add(_RowSummary(y: y, rMax: rMax, rMin: rMin,
          transitions: transitions));
    }

    if (globalRange < minRange || rowSummaries.length < 3) return null;
    if (bestTransitions < minBarcodeTransitions) return null;

    // ── Pass 2: classify rows, compute element ERN for normal rows ────────────
    // Damaged = valid barcode row but with fewer bar-space transitions than
    // expected. The blue-marker case: ink fuses bars together → transitions drop.
    final damagedThreshold = max(minBarcodeTransitions,
        (bestTransitions * 0.50).round());

    int damagedRows = 0;
    final normalRowDEFs = <double>[];
    int barVoteCount = 0;

    for (final row in rowSummaries) {
      if (row.transitions < damagedThreshold) {
        // Structural damage: row has fewer bar-space crossings than a healthy row.
        damagedRows++;
        continue; // don't contribute to element-level DEF calculation
      }

      final base = row.y * W + x0;
      if (base + roiW > bytes.length) continue;
      final rowVals = List<double>.filled(roiW, 0.0);
      for (int x = 0; x < roiW; x++) rowVals[x] = bytes[base + x] / 255.0;

      final edges = _detectEdges(rowVals, row.rMax, row.rMin);
      if (edges.length < 4) continue;

      final edgePos = edges.map((e) => e.position).toList();
      final boundaries = <double>[0, ...edgePos, rowVals.length.toDouble()];
      final midpoint = (row.rMin + row.rMax) / 2;

      double worstRowERN = 0.0;
      bool worstRowIsBar = false;

      // Contamination check: dark ink in bright (space) elements.
      // Marker/rotulador ink creates dark pixels within space elements that
      // should be bright. ERN alone underdetects diagonal marks because a
      // diagonal line crosses each element at only one point.
      // Threshold 0.38: below this inside a space element = contamination.
      const contamThreshold = 0.38;
      double worstContamSeverity = 0.0;

      for (int i = 0; i < boundaries.length - 1; i++) {
        final start = boundaries[i].round().clamp(0, rowVals.length - 1);
        final end   = boundaries[i + 1].round().clamp(start, rowVals.length);
        if (end - start < 3) continue;

        double eMin = rowVals[start], eMax = rowVals[start], eSum = 0;
        for (int j = start; j < end; j++) {
          if (rowVals[j] < eMin) eMin = rowVals[j];
          if (rowVals[j] > eMax) eMax = rowVals[j];
          eSum += rowVals[j];
        }
        final ern = eMax - eMin;
        final avg = eSum / (end - start);
        if (ern > worstRowERN) {
          worstRowERN = ern;
          worstRowIsBar = avg < midpoint;
        }
        // Contamination: space elements (avg > midpoint) with dark pixels
        if (avg > midpoint && eMin < contamThreshold) {
          final severity = (contamThreshold - eMin) / contamThreshold;
          if (severity > worstContamSeverity) worstContamSeverity = severity;
        }
      }

      // Contamination DEF contribution (severity × 0.90):
      //   severity 0.30 (min≈0.27) → 0.27 DEF (Grade C/D)
      //   severity 0.60 (min≈0.15) → 0.54 DEF (Grade F)
      //   severity 1.00 (min=0.00) → 0.90 DEF (Grade F)
      final contamDEF = worstContamSeverity * 0.90;

      // Take the worst of ERN-based DEF and contamination DEF.
      final rowDEF =
          max(globalRange > 0 ? worstRowERN / globalRange : 0.0, contamDEF);
      normalRowDEFs.add(rowDEF);
      if (worstRowIsBar) barVoteCount++;
    }

    if (normalRowDEFs.isEmpty && damagedRows == 0) return null;

    // ── Pass 3: combine element DEF + structural penalty ──────────────────────
    double elementDEF = 0.0;
    if (normalRowDEFs.isNotEmpty) {
      normalRowDEFs.sort();
      final p80idx = ((normalRowDEFs.length - 1) * 0.80).round();
      elementDEF = normalRowDEFs[p80idx].clamp(0.0, 1.0);
    }

    final totalBarcodeRows = rowSummaries.length;
    final damagedFraction =
        totalBarcodeRows > 0 ? damagedRows / totalBarcodeRows : 0.0;
    final structuralDEF = _structuralDEFFromFraction(damagedFraction);

    final def = max(elementDEF, structuralDEF);

    if (damagedFraction >= 0.15) {
      return _defGradeValue(def, '~Cámara · barras-rotas');
    }
    final worstIsBar = normalRowDEFs.isNotEmpty
        ? barVoteCount / normalRowDEFs.length >= 0.5
        : false;
    return _defGradeValue(def, '~Cámara · ${worstIsBar ? 'void' : 'spot'}');
  }

  // Converts fraction of structurally damaged rows to a DEF score.
  // "Damaged row" = barcode row with < 50% of best-row transition count,
  // meaning bars are fused, torn, or heavily contaminated.
  double _structuralDEFFromFraction(double fraction) {
    if (fraction >= 0.35) return 0.75; // Grade F
    if (fraction >= 0.25) return 0.50; // Grade D
    if (fraction >= 0.15) return 0.35; // Grade C
    if (fraction >= 0.08) return 0.22; // Grade B boundary
    return 0.0;                         // No structural penalty
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

    // Size check: quiet zone in modules
    final leftQZ = bb.left;
    final rightQZ = input.captureSize.width - bb.right;
    final minQZ = leftQZ < rightQZ ? leftQZ : rightQZ;
    final modW = bb.width > 0 ? bb.width / _expectedModuleCount(input.symbology) : 1.0;
    final qzMods = modW > 0 ? minQZ / modW : 0.0;
    final req = _requiredQuietZone(input.symbology);
    ISOGrade sizeGrade;
    if (qzMods >= req) sizeGrade = ISOGrade.A;
    else if (qzMods >= req * 0.8) sizeGrade = ISOGrade.B;
    else if (qzMods >= req * 0.6) sizeGrade = ISOGrade.C;
    else if (qzMods >= req * 0.4) sizeGrade = ISOGrade.D;
    else sizeGrade = ISOGrade.F;

    // Contamination check: dark pixels in the quiet zone area (ink smears, fingerprints).
    // The quiet zone must be white — any significant dark area degrades the grade.
    final contamGrade = _checkQZContamination(input, bb, modW);
    final worst = (contamGrade != null && contamGrade.numeric < sizeGrade.numeric)
        ? contamGrade
        : sizeGrade;

    final isContaminated = contamGrade != null && contamGrade.numeric < sizeGrade.numeric;
    return GradeValue(
      rawMeasurement: qzMods, unit: 'X', grade: worst,
      numericGrade: worst.numeric,
      isEstimated: isContaminated,
      estimationBasis: isContaminated ? 'Contaminación en zona silenciosa' : null,
    );
  }

  // Checks pixel darkness in the left/right quiet zones using NV21 Y-plane.
  // Returns the contamination grade (A=clean … F=heavily contaminated), or null
  // if image data is unavailable.
  ISOGrade? _checkQZContamination(
      BarcodeAnalysisInput input, Rect bb, double modW) {
    final bytes = input.imageBytes;
    if (bytes == null) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // Only NV21
    if (bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return null;
    if (bytes.length < W * H) return null;

    // Sample a strip of pixels the width of 2 modules inside the quiet zone,
    // vertically aligned with the barcode rows.
    final sampleW = (modW * 2).round().clamp(4, 40);
    final y0 = bb.top.toInt().clamp(0, H - 1);
    final y1 = bb.bottom.toInt().clamp(y0 + 1, H);

    final lx0 = (bb.left.toInt() - sampleW).clamp(0, W - 1);
    final lx1 = bb.left.toInt().clamp(lx0 + 1, W);
    final rx0 = bb.right.toInt().clamp(0, W - 1);
    final rx1 = (bb.right.toInt() + sampleW).clamp(rx0 + 1, W);

    if (lx1 - lx0 < 2 && rx1 - rx0 < 2) return null;

    int total = 0, dark = 0;
    const step = 2;
    // Pixel is "dark" (contamination) if luminance < 50% (128/255).
    // Normal white label paper: Y ≈ 200-240. Ink smear: Y ≈ 20-80.
    const darkThreshold = 128;

    for (int y = y0; y < y1; y += step) {
      final rowBase = y * W;
      for (int x = lx0; x < lx1; x += step) {
        final idx = rowBase + x;
        if (idx >= bytes.length) continue;
        total++;
        if (bytes[idx] < darkThreshold) dark++;
      }
      for (int x = rx0; x < rx1; x += step) {
        final idx = rowBase + x;
        if (idx >= bytes.length) continue;
        total++;
        if (bytes[idx] < darkThreshold) dark++;
      }
    }

    if (total < 10) return null;
    final ratio = dark / total;

    if (ratio <= 0.05) return ISOGrade.A;  // < 5%: zona limpia
    if (ratio <= 0.12) return ISOGrade.B;  // 5-12%: leve contaminación
    if (ratio <= 0.22) return ISOGrade.C;  // 12-22%: contaminación notable
    if (ratio <= 0.38) return ISOGrade.D;  // 22-38%: contaminación significativa
    return ISOGrade.F;                      // > 38%: zona severamente contaminada
  }

  // ── Conservative fallback ─────────────────────────────────────────────────

  ISOParameters _conservativeFallback(bool decoded, BarcodeAnalysisInput input) {
    final g = decoded ? ISOGrade.C : ISOGrade.F;
    const basis = 'Estimación — sin imagen analizable';
    GradeValue est(double raw, String unit) => GradeValue(
      rawMeasurement: raw, unit: unit, grade: g, numericGrade: g.numeric,
      isEstimated: true, estimationBasis: basis,
    );
    return ISOParameters(
      symbolContrast: est(decoded ? 40.0 : 10.0, '%'),
      minimumReflectance: est(decoded ? 30.0 : 80.0, '%'),
      edgeContrast: est(decoded ? 0.40 : 0.05, 'ratio'),
      modulation: est(decoded ? 0.50 : 0.05, 'ratio'),
      defects: est(decoded ? 0.20 : 0.90, 'ratio'),
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

class _RowSummary {
  final int y, transitions;
  final double rMax, rMin;
  _RowSummary({required this.y, required this.transitions,
      required this.rMax, required this.rMin});
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
    final mod = metrics != null ? _calcMODFromMetrics(metrics) : _est(decoded, 0.50, 0.05, 'ratio');
    final def = metrics != null ? _calcDEFFromMetrics(metrics) : _est(decoded, 0.20, 0.90, 'ratio');
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

  // ── 2D metrics extraction ─────────────────────────────────────────────────

  _2DMetrics? _extract2DMetrics(BarcodeAnalysisInput input) {
    final bytes = input.imageBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final W = input.captureSize.width.round();
    final H = input.captureSize.height.round();
    if (W <= 0 || H <= 0) return null;

    // 3-byte JPEG check prevents false positive with bright NV21 frames.
    if (bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return _metricsFromJpeg(bytes, input);
    }
    if (bytes.length >= W * H) return _metricsFromYPlane(bytes, W, H, input);
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
      // Tighter fallback ROI — wide ROI biases mean towards white background.
      x0 = W ~/ 3; x1 = 2 * W ~/ 3;
      y0 = H ~/ 3; y1 = 2 * H ~/ 3;
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

  _2DMetrics? _metricsFromJpeg(List<int> bytes, BarcodeAnalysisInput input) =>
      null;

  // ── 2D photometric parameters ─────────────────────────────────────────────

  // SC: Michelson from NV21 Y-plane — real measurement.
  GradeValue _calcSCFromMetrics(_2DMetrics m) {
    final michelson = (m.rMax - m.rMin) / (m.rMax + m.rMin + 0.001);
    final pct = michelson * 100.0;
    ISOGrade g;
    if (pct >= 70) g = ISOGrade.A;
    else if (pct >= 55) g = ISOGrade.B;
    else if (pct >= 40) g = ISOGrade.C;
    else if (pct >= 20) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pct, unit: '%', grade: g, numericGrade: g.numeric);
  }

  // MOD: bimodality proxy — a well-modulated QR has high std dev relative to range.
  GradeValue _calcMODFromMetrics(_2DMetrics m) {
    final range = m.rMax - m.rMin;
    // Bimodal distribution (50% dark/50% light, mean at midpoint): stdDev/range ≈ 0.5.
    // Scale ×2 so a perfect QR gives mod ≈ 1.0.
    final mod = range > 0 ? ((m.stdDev / range) * 2).clamp(0.0, 1.0) : 0.0;
    ISOGrade g;
    if (mod >= 0.70) g = ISOGrade.A;
    else if (mod >= 0.55) g = ISOGrade.B;
    else if (mod >= 0.40) g = ISOGrade.C;
    else if (mod >= 0.25) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: mod, unit: 'ratio', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
  }

  // DEF: how far the actual mean deviates from the ideal midpoint (dark/light balance).
  GradeValue _calcDEFFromMetrics(_2DMetrics m) {
    final range = m.rMax - m.rMin;
    final expectedMean = (m.rMin + m.rMax) / 2;
    // Normalize: max deviation is 0.5×range (mean at one extreme) → scale to 0-1.
    final def = range > 0
        ? ((m.mean - expectedMean).abs() / range).clamp(0.0, 1.0)
        : 1.0;
    ISOGrade g;
    if (def <= 0.15) g = ISOGrade.A;
    else if (def <= 0.20) g = ISOGrade.B;
    else if (def <= 0.30) g = ISOGrade.C;
    else if (def <= 0.40) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: def, unit: 'ratio', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
  }

  // PG: print growth (ink gain) — inferred from mean vs ideal midpoint.
  // Tight ROI (bounding box) reduces background bias.
  GradeValue _calcPGFromMetrics(_2DMetrics m) {
    // Mean below midpoint → too much ink (print gain). Above → too little.
    final midpoint = (m.rMin + m.rMax) / 2;
    final deviation = (m.mean - midpoint).abs();
    final range = m.rMax - m.rMin;
    // Express as % of range so it's comparable across different contrast levels.
    final pg = range > 0 ? (deviation / range * 100.0).clamp(0.0, 50.0) : 50.0;
    ISOGrade g;
    if (pg <= 10.0) g = ISOGrade.A;
    else if (pg <= 15.0) g = ISOGrade.B;
    else if (pg <= 22.0) g = ISOGrade.C;
    else if (pg <= 30.0) g = ISOGrade.D;
    else g = ISOGrade.F;
    return GradeValue(rawMeasurement: pg, unit: '%', grade: g,
      numericGrade: g.numeric, isEstimated: true, estimationBasis: '~Cámara');
  }

  // ── 2D geometric parameters ───────────────────────────────────────────────

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
