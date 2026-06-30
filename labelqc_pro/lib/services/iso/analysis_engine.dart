import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import '../../domain/entities/entities.dart';
import 'iso_analyzers.dart';

/// Motor central de análisis de calidad de impresión.
///
/// Encapsula TODO el pipeline desde bytes NV21 brutos hasta veredicto final:
///   1. Validación del frame (NV21 vs JPEG, tamaño, bytes)
///   2. Detección de orientación del sensor
///   3. Recorte al área del código (ROI)
///   4. Puertas de confianza (tamaño mínimo, contraste, transiciones, filas)
///   5. Análisis ISO 15416/15415
///   6. Veredicto con evidencia trazable
///
/// Los scan screens solo llaman a [analyze] y consumen [AnalysisResult].
/// Todo el procesamiento NV21, rotación y validación ocurre aquí.
class BarcodeAnalysisEngine {
  final ISO15416Analyzer _analyzer1D;
  final ISO15415Analyzer _analyzer2D;

  // ── Confidence gate thresholds ──────────────────────────────────────────
  /// Ancho mínimo del crop en píxeles. Un Code128 necesita al menos 50px para
  /// distinguir módulos individuales con la cámara.
  static const _minCropW = 50;

  /// Alto mínimo del crop en píxeles.
  static const _minCropH = 8;

  /// Luminancia máxima mínima del crop. Si rMax < 0.40 la imagen está muy oscura.
  static const _minRMax = 0.40;

  /// Rango mínimo de contraste en el crop (rMax - rMin). < 0.20 = sin barras visibles.
  static const _minContrast = 0.20;

  /// Mínimo de transiciones barra/espacio en la mejor fila del crop.
  static const _minTransitions = 8;

  /// Mínimo de filas con patrón barcode válido en el crop.
  static const _minBarcodeRows = 3;

  BarcodeAnalysisEngine({
    ISO15416Analyzer? analyzer1D,
    ISO15415Analyzer? analyzer2D,
  })  : _analyzer1D = analyzer1D ?? ISO15416Analyzer(),
        _analyzer2D = analyzer2D ?? ISO15415Analyzer();

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  AnalysisResult analyze({
    required Uint8List? rawBytes,
    required Size captureSize,
    required List<Offset>? corners,
    required String? rawValue,
    required BarcodeType symbology,
  }) {
    final displayBB = _cornersToRect(corners);

    // ── 1. Frame validation ────────────────────────────────────────────────
    final baseEvidence = AnalysisEvidence(
      isNV21: false,
      nativeW: captureSize.width.round(),
      nativeH: captureSize.height.round(),
    );

    if (rawBytes == null || rawBytes.isEmpty) {
      return AnalysisResult.repetir(RepeatReason.sinImagen, evidence: baseEvidence);
    }

    if (_isJpeg(rawBytes)) {
      // JPEG fue post-procesado por el ISP — píxeles alterados, no analizables.
      return AnalysisResult.repetir(RepeatReason.sinImagen, evidence: baseEvidence);
    }

    final cW = captureSize.width.round();
    final cH = captureSize.height.round();
    if (cW <= 0 || cH <= 0 || rawBytes.length < cW * cH) {
      return AnalysisResult.repetir(RepeatReason.sinImagen, evidence: baseEvidence);
    }

    // ── 2. Orientation resolution ──────────────────────────────────────────
    final (nW, nH, nativeBB, corrected) =
        _resolveLayout(rawBytes, cW, cH, displayBB);

    final preEvidence = AnalysisEvidence(
      isNV21: true,
      nativeW: nW,
      nativeH: nH,
      wasOrientationCorrected: corrected,
    );

    // ── 3. ROI crop ────────────────────────────────────────────────────────
    final crop = _cropROI(rawBytes, nW, nH, nativeBB);
    if (crop == null) {
      return AnalysisResult.repetir(
        RepeatReason.cropDemasiadoPequeno,
        evidence: preEvidence,
      );
    }
    final (cropBytes, cx0, cy0, cropW, cropH) = crop;

    // ── 4. Confidence gates ────────────────────────────────────────────────
    final probe = _probeFrame(cropBytes, cropW, cropH);

    final gateEvidence = AnalysisEvidence(
      isNV21: true,
      nativeW: nW,
      nativeH: nH,
      wasOrientationCorrected: corrected,
      cropX0: cx0,
      cropY0: cy0,
      cropW: cropW,
      cropH: cropH,
      cropContrast: probe.rMax - probe.rMin,
      bestTransitions: probe.bestTransitions,
      barcodeRows: probe.barcodeRowCount,
    );

    if (probe.rMax < _minRMax) {
      return AnalysisResult.repetir(RepeatReason.imagenOscura, evidence: gateEvidence);
    }
    if (probe.rMax - probe.rMin < _minContrast) {
      return AnalysisResult.repetir(RepeatReason.bajoContrastePared, evidence: gateEvidence);
    }
    if (probe.bestTransitions < _minTransitions) {
      return AnalysisResult.repetir(RepeatReason.pocasTransiciones, evidence: gateEvidence);
    }
    if (probe.barcodeRowCount < _minBarcodeRows) {
      return AnalysisResult.repetir(RepeatReason.pocasFilas, evidence: gateEvidence);
    }

    // ── 5. ISO analysis ────────────────────────────────────────────────────
    final input = BarcodeAnalysisInput(
      rawValue: rawValue,
      symbology: symbology,
      corners: corners,
      boundingBox: Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
      captureSize: Size(cropW.toDouble(), cropH.toDouble()),
      imageBytes: cropBytes,
    );

    final params = symbology.is2D
        ? _analyzer2D.analyze(input)
        : _analyzer1D.analyze(input);

    final grade = params.overallGrade;

    // ── 6. Verdict + evidence ──────────────────────────────────────────────
    final verdict = grade.numeric >= ISOGrade.C.numeric
        ? AnalysisVerdict.pasa
        : AnalysisVerdict.noPasa;

    final evidence = AnalysisEvidence(
      isNV21: true,
      nativeW: nW,
      nativeH: nH,
      wasOrientationCorrected: corrected,
      cropX0: cx0,
      cropY0: cy0,
      cropW: cropW,
      cropH: cropH,
      cropContrast: probe.rMax - probe.rMin,
      bestTransitions: probe.bestTransitions,
      barcodeRows: probe.barcodeRowCount,
      scRaw: params.symbolContrast.isEstimated
          ? null
          : params.symbolContrast.rawMeasurement,
      defRaw: params.defects.rawMeasurement,
      defEstimationBasis: params.defects.estimationBasis,
    );

    return AnalysisResult(
      verdict: verdict,
      parameters: params,
      overallGrade: grade,
      failCause: verdict == AnalysisVerdict.noPasa
          ? _determineFailCause(params)
          : null,
      evidence: evidence,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE — Frame processing
  // ─────────────────────────────────────────────────────────────────────────

  bool _isJpeg(Uint8List b) =>
      b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  /// Detecta orientación NV21 real probando ambas (portrait vs landscape).
  /// Cuenta transiciones barra/espacio en la fila central del BB en cada layout.
  /// El layout con más transiciones es el correcto (más barra/espacios visibles).
  ///
  /// Returns (nativeW, nativeH, nativeBB, wasOrientationCorrected).
  (int, int, Rect?, bool) _resolveLayout(
      Uint8List bytes, int cW, int cH, Rect? displayBB) {
    if (cW >= cH) {
      // Ya en landscape — NV21 coincide con captureSize.
      return (cW, cH, displayBB, false);
    }

    // Portrait display: NV21 podría ser landscape (sensor nativo cH×cW).
    final tPortrait = _countTransitions(bytes, cW, cH, displayBB);

    // Mapeo 90° CW: sensor_x = cH-1-display_y, sensor_y = display_x.
    final landscapeBB = displayBB != null
        ? Rect.fromLTRB(
            ((cH - 1) - displayBB.bottom).clamp(0.0, (cH - 1).toDouble()),
            displayBB.left.clamp(0.0, (cW - 1).toDouble()),
            ((cH - 1) - displayBB.top).clamp(0.0, (cH - 1).toDouble()),
            displayBB.right.clamp(0.0, (cW - 1).toDouble()),
          )
        : null;
    final tLandscape = _countTransitions(bytes, cH, cW, landscapeBB);

    if (tLandscape > tPortrait * 1.3) {
      return (cH, cW, landscapeBB, true);
    }
    return (cW, cH, displayBB, false);
  }

  /// Cuenta transiciones barra/espacio en la fila central del BB.
  int _countTransitions(Uint8List bytes, int W, int H, Rect? bb) {
    if (W <= 0 || H <= 0 || bytes.length < W * H) return 0;
    final cy = bb != null
        ? ((bb.top + bb.bottom) / 2).round().clamp(0, H - 1)
        : H ~/ 2;
    final x0 = bb != null ? bb.left.toInt().clamp(0, W - 1) : W ~/ 4;
    final x1 = bb != null ? bb.right.toInt().clamp(x0 + 1, W) : 3 * W ~/ 4;
    if (x1 - x0 < 20) return 0;
    final rowBase = cy * W;
    if (rowBase + x1 > bytes.length) return 0;

    int lo = 255, hi = 0;
    for (int x = x0; x < x1; x++) {
      final v = bytes[rowBase + x];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (hi - lo < 30) return 0;
    final thresh = (lo + hi) ~/ 2;
    int trans = 0;
    bool prev = bytes[rowBase + x0] >= thresh;
    for (int x = x0 + 1; x < x1; x++) {
      final cur = bytes[rowBase + x] >= thresh;
      if (cur != prev) { trans++; prev = cur; }
    }
    return trans;
  }

  /// Recorta el plano Y del NV21 al BB del código + padding.
  /// Returns (cropBytes, cropX0, cropY0, cropW, cropH) o null si inválido.
  (Uint8List, int, int, int, int)? _cropROI(
      Uint8List bytes, int nW, int nH, Rect? nativeBB) {
    if (nativeBB == null || nW <= 0 || nH <= 0 || bytes.length < nW * nH) {
      return null;
    }
    const pad = 12;
    final x0 = (nativeBB.left.toInt() - pad).clamp(0, nW - 1);
    final x1 = (nativeBB.right.toInt() + pad).clamp(x0 + 1, nW);
    final y0 = (nativeBB.top.toInt() - pad).clamp(0, nH - 1);
    final y1 = (nativeBB.bottom.toInt() + pad).clamp(y0 + 1, nH);
    final cropW = x1 - x0;
    final cropH = y1 - y0;

    if (cropW < _minCropW || cropH < _minCropH) return null;

    final crop = Uint8List(cropW * cropH);
    for (int y = 0; y < cropH; y++) {
      final src = (y0 + y) * nW + x0;
      if (src + cropW > bytes.length) break;
      crop.setRange(y * cropW, y * cropW + cropW, bytes, src);
    }
    return (crop, x0, y0, cropW, cropH);
  }

  /// Sondeo rápido del crop: rango de contraste, mejores transiciones, filas válidas.
  /// Permite evaluar las confidence gates sin ejecutar el análisis ISO completo.
  _FrameProbe _probeFrame(Uint8List bytes, int W, int H) {
    double rMax = 0, rMin = 1;
    int bestTransitions = 0;
    int barcodeRowCount = 0;

    for (int y = 0; y < H; y += 2) {
      final rowBase = y * W;
      if (rowBase + W > bytes.length) break;

      double lo = 1, hi = 0;
      for (int x = 0; x < W; x++) {
        final v = bytes[rowBase + x] / 255.0;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      if (hi > rMax) rMax = hi;
      if (lo < rMin) rMin = lo;

      final range = hi - lo;
      if (range < 0.15) continue;

      final thresh = (lo + hi) / 2;
      int trans = 0;
      bool prev = bytes[rowBase] / 255.0 >= thresh;
      for (int x = 1; x < W; x++) {
        final cur = bytes[rowBase + x] / 255.0 >= thresh;
        if (cur != prev) { trans++; prev = cur; }
      }
      if (trans > bestTransitions) bestTransitions = trans;
      if (trans >= _minTransitions) barcodeRowCount++;
    }

    return _FrameProbe(
      rMax: rMax,
      rMin: rMin,
      bestTransitions: bestTransitions,
      barcodeRowCount: barcodeRowCount,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE — Verdict helpers
  // ─────────────────────────────────────────────────────────────────────────

  FailCause _determineFailCause(ISOParameters params) {
    // Decodability es siempre lo primero — si no decodifica, no hay nada más.
    if (params.decodability.grade == ISOGrade.F) return FailCause.noDecodificado;

    // DEF: interpretar la causa física desde el estimationBasis.
    final defBasis = params.defects.estimationBasis ?? '';
    if (params.defects.grade.numeric < ISOGrade.C.numeric) {
      if (defBasis.contains('barras-rotas')) return FailCause.barrasDanadas;
      // Contaminación con alta severidad en espacios = rotulador o mancha.
      if (defBasis.contains('spot')) return FailCause.manchaContaminacion;
      if (defBasis.contains('void')) return FailCause.manchaContaminacion;
      return FailCause.rotulador;
    }

    // SC bajo → ribbon o cabezal sin tinta.
    if (params.symbolContrast.grade.numeric < ISOGrade.C.numeric) {
      return FailCause.bajoContraste;
    }

    return FailCause.imagenInsuficiente;
  }

  Rect? _cornersToRect(List<Offset>? corners) {
    if (corners == null || corners.isEmpty) return null;
    double minX = corners[0].dx, maxX = corners[0].dx;
    double minY = corners[0].dy, maxY = corners[0].dy;
    for (final c in corners) {
      if (c.dx < minX) minX = c.dx;
      if (c.dx > maxX) maxX = c.dx;
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }
    if (maxX <= minX || maxY <= minY) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Resultado del sondeo rápido del crop.
class _FrameProbe {
  final double rMax;
  final double rMin;
  final int bestTransitions;
  final int barcodeRowCount;
  const _FrameProbe({
    required this.rMax,
    required this.rMin,
    required this.bestTransitions,
    required this.barcodeRowCount,
  });
}
