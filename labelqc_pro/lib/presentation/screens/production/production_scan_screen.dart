import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../../domain/entities/entities.dart';
import '../../../services/iso/iso_analyzers.dart';
import '../../../services/spc/spc_and_recommendations.dart';
import '../../../data/datasources/local/database/app_database.dart';
import '../../../injection.dart';

class ProductionScanScreen extends StatefulWidget {
  const ProductionScanScreen({super.key});

  @override
  State<ProductionScanScreen> createState() => _ProductionScanScreenState();
}

class _ProductionScanScreenState extends State<ProductionScanScreen>
    with TickerProviderStateMixin {
  // Normal speed: fires every ~200ms so _pendingCapture is always a fresh frame.
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.all],
    returnImage: true,
  );

  bool _torchOn = false;
  bool _isAnalyzing = false;
  bool _isStabilizing = false; // 400ms pause after capture button press
  bool _showResult = false;
  bool _isBlurry = false;
  BarcodeVerification? _lastResult;
  ISOGrade _minGrade = ISOGrade.C;

  // The last barcode detected in the scan zone — updated continuously.
  // Null means no barcode currently in zone.
  BarcodeCapture? _pendingCapture;
  bool _barcodeInZone = false;

  // Clears the zone indicator if no detection arrives for 1.5s
  // (barcode left the frame or moved out of zone).
  Timer? _clearZoneTimer;

  late AnimationController _resultAnim;
  late Animation<double> _resultScale;
  late AnimationController _pulseAnim;

  final ISO15415Analyzer _analyzer2D = ISO15415Analyzer();
  final ISO15416Analyzer _analyzer1D = ISO15416Analyzer();
  final RecommendationEngine _recEngine = RecommendationEngine();

  @override
  void initState() {
    super.initState();
    _resultAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _resultScale =
        CurvedAnimation(parent: _resultAnim, curve: Curves.elasticOut);
    _pulseAnim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
        lowerBound: 0.85,
        upperBound: 1.0)
      ..repeat(reverse: true);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = getIt<AppDatabase>();
    final gradeStr = await db.getSetting('min_acceptable_grade') ?? 'C';
    final grade = ISOGrade.values.firstWhere(
      (g) => g.letter == gradeStr,
      orElse: () => ISOGrade.C,
    );
    if (mounted) setState(() => _minGrade = grade);
  }

  @override
  void dispose() {
    _scanner.dispose();
    _resultAnim.dispose();
    _pulseAnim.dispose();
    _clearZoneTimer?.cancel();
    super.dispose();
  }

  // Called continuously by mobile_scanner (~200ms intervals).
  // Only stores the capture — does NOT analyze. Analysis runs on button press.
  void _onDetect(BarcodeCapture capture) {
    if (_isAnalyzing || _showResult) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final bbox = _cornersToRect(barcode.corners);
    if (!_isValidDetection(capture, barcode)) return;

    final blurry = !_isSharpEnough(capture.image, capture.size, bbox);

    // Restart the "barcode left frame" timer on every fresh detection.
    _clearZoneTimer?.cancel();
    _clearZoneTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _barcodeInZone = false;
          _pendingCapture = null;
          _isBlurry = false;
        });
      }
    });

    if (mounted) {
      setState(() {
        _pendingCapture = capture;
        _barcodeInZone = true;
        _isBlurry = blurry;
      });
    }
  }

  // Triggered by the capture button. Waits 400ms so auto-focus can settle and
  // onDetect refreshes _pendingCapture with the sharpest available frame.
  Future<void> _onCapturePressed() async {
    if (_pendingCapture == null || _isAnalyzing || _showResult || _isStabilizing) return;

    setState(() { _isStabilizing = true; });
    // During this 400ms the scanner keeps running and _pendingCapture updates
    // to the most recent detected frame — ensures we analyse a fresh sharp image.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final capture = _pendingCapture;
    if (capture == null) {
      setState(() { _isStabilizing = false; });
      return;
    }

    // Snapshot immediately to avoid race with next onDetect call.
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) {
      setState(() { _isStabilizing = false; });
      return;
    }

    _clearZoneTimer?.cancel();
    setState(() {
      _isStabilizing = false;
      _isAnalyzing = true;
      _barcodeInZone = false;
      _pendingCapture = null;
      _isBlurry = false;
    });

    HapticFeedback.mediumImpact();

    try {
      final type = _mapFormat(barcode.format);

      // ── NV21 crop to barcode region ──────────────────────────────────────
      // mobile_scanner on Android returns NV21 bytes in SENSOR (landscape)
      // orientation, but capture.size and barcode.corners are in DISPLAY
      // (portrait) orientation. Indexing with display coordinates on landscape
      // bytes reads diagonal lines → garbage luminance → always F.
      //
      // Fix: detect the actual NV21 layout, map corners to sensor coords,
      // crop ONLY the barcode pixels, and pass the clean crop to the analyzer.
      final rawImage = capture.image;
      final displayBB = _cornersToRect(barcode.corners);
      final BarcodeAnalysisInput input;

      if (rawImage != null && !_isJpeg(rawImage)) {
        final layout = _resolveNV21Layout(rawImage, capture.size, displayBB);
        final crop = _cropBarcodeNV21(
            rawImage, layout.$1, layout.$2, layout.$3);
        if (crop != null) {
          // Analyzer receives a clean, barcode-only image.
          // BoundingBox = whole image (no margins, no background).
          input = BarcodeAnalysisInput(
            rawValue: barcode.rawValue,
            symbology: type,
            corners: barcode.corners,
            boundingBox: Rect.fromLTWH(0, 0, crop.$2.width, crop.$2.height),
            captureSize: crop.$2,
            imageBytes: crop.$1,
          );
        } else {
          // Crop failed (e.g. no bounding box) — fall back to full frame.
          input = BarcodeAnalysisInput(
            rawValue: barcode.rawValue,
            symbology: type,
            corners: barcode.corners,
            boundingBox: displayBB,
            captureSize: capture.size,
            imageBytes: rawImage,
          );
        }
      } else {
        input = BarcodeAnalysisInput(
          rawValue: barcode.rawValue,
          symbology: type,
          corners: barcode.corners,
          boundingBox: displayBB,
          captureSize: capture.size,
          imageBytes: rawImage,
        );
      }

      final params =
          type.is2D ? _analyzer2D.analyze(input) : _analyzer1D.analyze(input);

      // Safety floor only when camera gave NO image bytes.
      final rawGrade = params.overallGrade;
      final effectiveGrade =
          (input.imageBytes == null && rawGrade.numeric < ISOGrade.C.numeric)
              ? ISOGrade.C
              : rawGrade;

      final recs = _recEngine.generate(
          verification: BarcodeVerification(
        id: '',
        timestamp: DateTime.now(),
        symbology: type,
        decodedValue: barcode.rawValue!,
        standard: type.standard,
        parameters: params,
        overallGrade: effectiveGrade,
        captureMode: OperatorMode.production,
      ));

      final verification = BarcodeVerification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        symbology: type,
        decodedValue: barcode.rawValue!,
        standard: type.standard,
        parameters: params,
        overallGrade: effectiveGrade,
        capturedImage: capture.image,
        captureMode: OperatorMode.production,
        recommendations: recs,
      );

      final isOk = effectiveGrade.numeric >= _minGrade.numeric;
      isOk ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();

      setState(() {
        _lastResult = verification;
        _isAnalyzing = false;
        _showResult = true;
      });
      _resultAnim.forward(from: 0);
    } catch (_) {
      setState(() => _isAnalyzing = false);
    }
  }

  void _continueScanning() {
    _resultAnim.reverse().then((_) {
      setState(() {
        _showResult = false;
        _lastResult = null;
      });
    });
  }

  // Sharpness check on the barcode row. If blurry → show warning but still
  // allow capture (the user decides, not the algorithm).
  bool _isSharpEnough(Uint8List? bytes, Size captureSize, Rect? bbox) {
    if (bytes == null) return true;
    final W = captureSize.width.round();
    final H = captureSize.height.round();
    if (W <= 0 || H <= 0 || bytes.length < W * H) return true;
    if (bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) return true;

    final y = bbox != null
        ? ((bbox.top + bbox.bottom) / 2).round().clamp(1, H - 2)
        : H ~/ 2;
    final x0 =
        bbox != null ? bbox.left.toInt().clamp(0, W - 1) : W ~/ 4;
    final x1 =
        bbox != null ? bbox.right.toInt().clamp(x0 + 1, W) : 3 * W ~/ 4;
    if (x1 - x0 < 10) return true;

    int lo = 255, hi = 0;
    for (int x = x0; x < x1; x++) {
      final v = bytes[y * W + x];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    if (range < 30) return true;

    double maxGrad = 0;
    for (int x = x0 + 1; x < x1; x++) {
      final grad =
          (bytes[y * W + x] - bytes[y * W + x - 1]).abs().toDouble();
      if (grad > maxGrad) maxGrad = grad;
    }
    return maxGrad / range >= 0.18;
  }

  bool _isValidDetection(BarcodeCapture capture, Barcode barcode) {
    final bb = _cornersToRect(barcode.corners);
    if (bb == null) return true;
    final frameW = capture.size.width;
    final frameH = capture.size.height;
    if (frameW <= 0 || frameH <= 0) return true;
    if (bb.width < frameW * 0.20) return false;
    final centerY = bb.center.dy;
    if (centerY < frameH * 0.20 || centerY > frameH * 0.80) return false;
    return true;
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
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  BarcodeType _mapFormat(BarcodeFormat f) {
    switch (f) {
      case BarcodeFormat.qrCode: return BarcodeType.qrCode;
      case BarcodeFormat.dataMatrix: return BarcodeType.dataMatrix;
      case BarcodeFormat.pdf417: return BarcodeType.pdf417;
      case BarcodeFormat.aztec: return BarcodeType.aztec;
      case BarcodeFormat.code128: return BarcodeType.code128;
      case BarcodeFormat.code39: return BarcodeType.code39;
      case BarcodeFormat.ean13: return BarcodeType.ean13;
      case BarcodeFormat.ean8: return BarcodeType.ean8;
      case BarcodeFormat.upcA: return BarcodeType.upcA;
      case BarcodeFormat.upcE: return BarcodeType.upcE;
      case BarcodeFormat.itf: return BarcodeType.itf;
      default: return BarcodeType.code128;
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoneColor = _barcodeInZone
        ? (_isBlurry ? const Color(0xFFFFC107) : AppColors.ok)
        : Colors.white.withOpacity(0.4);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            overlayBuilder: (context, constraints) =>
                const SizedBox.shrink(),
          ),

          // Scan zone overlay
          if (!_showResult)
            Positioned.fill(
              child: LayoutBuilder(builder: (_, constraints) {
                final h = constraints.maxHeight;
                final zoneH = h * 0.30;
                final zoneTop = (h - zoneH) / 2;
                return Stack(children: [
                  Positioned(
                      top: 0, left: 0, right: 0, height: zoneTop,
                      child: Container(color: Colors.black.withOpacity(0.55))),
                  Positioned(
                      bottom: 0, left: 0, right: 0, height: zoneTop,
                      child: Container(color: Colors.black.withOpacity(0.55))),
                  Positioned(
                    top: zoneTop, left: 16, right: 16, height: zoneH,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: zoneColor, width: 2),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                  // Zone status label
                  Positioned(
                    top: zoneTop - 28,
                    left: 0, right: 0,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _barcodeInZone
                            ? Container(
                                key: const ValueKey('detected'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _isBlurry
                                      ? const Color(0xFFFFC107).withOpacity(0.15)
                                      : AppColors.ok.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: _isBlurry
                                          ? const Color(0xFFFFC107)
                                              .withOpacity(0.6)
                                          : AppColors.ok.withOpacity(0.6)),
                                ),
                                child: Text(
                                  _isBlurry
                                      ? '⚠ Imagen borrosa · Acerque el teléfono'
                                      : '● Código detectado · Pulse capturar',
                                  style: TextStyle(
                                    color: _isBlurry
                                        ? const Color(0xFFFFC107)
                                        : AppColors.ok,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),
                    ),
                  ),
                ]);
              }),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _camBtn(
                      Icons.arrow_back_rounded, () => context.pop()),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.ok.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                              color: AppColors.ok,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        const Text('PRODUCCIÓN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ok,
                              letterSpacing: 1.2,
                            )),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _camBtn(
                    _torchOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    () {
                      _scanner.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Analyzing indicator
          if (_isAnalyzing)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Analizando...',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),

          // Capture button
          if (!_showResult && !_isAnalyzing)
            Positioned(
              bottom: 40,
              left: 0, right: 0,
              child: Column(
                children: [
                  // Hint / stabilizing label
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isStabilizing
                        ? Container(
                            key: const ValueKey('stabilizing'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.accent.withOpacity(0.5)),
                            ),
                            child: const Text(
                              '⟳  Enfocando...',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : Text(
                            key: const ValueKey('hint'),
                            _barcodeInZone ? '' : 'Apunta al código · Pulsa capturar',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 12,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  // Shutter button
                  GestureDetector(
                    onTap: (_barcodeInZone && !_isStabilizing)
                        ? _onCapturePressed
                        : null,
                    child: ScaleTransition(
                      scale: (_barcodeInZone && !_isStabilizing)
                          ? _pulseAnim
                          : const AlwaysStoppedAnimation(1.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isStabilizing
                              ? AppColors.accent
                              : _barcodeInZone
                                  ? (_isBlurry
                                      ? const Color(0xFFFFC107)
                                      : AppColors.ok)
                                  : Colors.white.withOpacity(0.15),
                          border: Border.all(
                              color: (_barcodeInZone || _isStabilizing)
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              width: 3),
                          boxShadow: (_barcodeInZone || _isStabilizing)
                              ? [
                                  BoxShadow(
                                    color: (_isStabilizing
                                            ? AppColors.accent
                                            : _isBlurry
                                                ? const Color(0xFFFFC107)
                                                : AppColors.ok)
                                        .withOpacity(0.5),
                                    blurRadius: 20,
                                    spreadRadius: 4,
                                  )
                                ]
                              : [],
                        ),
                        child: _isStabilizing
                            ? const SizedBox(
                                width: 28, height: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt_rounded,
                                color: _barcodeInZone
                                    ? Colors.black
                                    : Colors.white.withOpacity(0.3),
                                size: 30,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isStabilizing ? 'ENFOCANDO' : 'CAPTURAR',
                    style: TextStyle(
                      color: (_barcodeInZone || _isStabilizing)
                          ? Colors.white
                          : Colors.white.withOpacity(0.25),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

          // Result overlay
          if (_showResult && _lastResult != null)
            Positioned.fill(
              child: ScaleTransition(
                scale: _resultScale,
                child: _ResultOverlay(
                  verification: _lastResult!,
                  isOk: _lastResult!.overallGrade.numeric >=
                      _minGrade.numeric,
                  onContinue: _continueScanning,
                  onDetail: () {
                    _continueScanning();
                    context.push('/technical/result',
                        extra: _lastResult);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── NV21 orientation detection & barcode crop ─────────────────────────────

  bool _isJpeg(Uint8List bytes) =>
      bytes.length > 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  /// Determines the true NV21 byte layout (sensor vs display orientation).
  ///
  /// Android camera sensors are landscape. When the phone is portrait,
  /// CameraX reports capture.size in display (portrait) coordinates but the
  /// NV21 bytes are stored in sensor (landscape) orientation.
  ///
  /// Strategy: test both layouts by counting bar-space transitions at the
  /// expected barcode center. Whichever gives more transitions is correct.
  ///
  /// Returns (nativeWidth, nativeHeight, nativeBoundingBox).
  (int, int, Rect?) _resolveNV21Layout(
      Uint8List bytes, Size captureSize, Rect? displayBB) {
    final cW = captureSize.width.round(); // display width
    final cH = captureSize.height.round(); // display height
    if (cW <= 0 || cH <= 0 || bytes.length < cW * cH) {
      return (cW, cH, displayBB);
    }
    // Already landscape: NV21 layout matches capture.size.
    if (cW >= cH) return (cW, cH, displayBB);

    // Portrait display → try landscape NV21 (sensor native: cH wide × cW tall).
    final tPortrait = _countTransitions(bytes, cW, cH, displayBB);

    // Coordinate mapping from display(portrait cW×cH) → sensor(landscape cH×cW)
    // via 90° CW rotation: sensor_x = cH-1-display_y, sensor_y = display_x.
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
      return (cH, cW, landscapeBB);
    }
    return (cW, cH, displayBB);
  }

  /// Counts bar-space transitions on the center row of the bounding box.
  /// More transitions = correct NV21 orientation.
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
    if (hi - lo < 30) return 0; // low contrast → can't count reliably
    final thresh = (lo + hi) ~/ 2;
    int trans = 0;
    bool wasLight = bytes[rowBase + x0] >= thresh;
    for (int x = x0 + 1; x < x1; x++) {
      final isLight = bytes[rowBase + x] >= thresh;
      if (isLight != wasLight) {
        trans++;
        wasLight = isLight;
      }
    }
    return trans;
  }

  /// Crops the NV21 Y-plane to the barcode region (+ padding).
  /// Returns (croppedLuminanceBytes, cropSize) or null if not feasible.
  (Uint8List, Size)? _cropBarcodeNV21(
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
    if (cropW < 20 || cropH < 5) return null;

    final crop = Uint8List(cropW * cropH);
    for (int y = 0; y < cropH; y++) {
      final src = (y0 + y) * nW + x0;
      if (src + cropW > bytes.length) break;
      crop.setRange(y * cropW, y * cropW + cropW, bytes, src);
    }
    return (crop, Size(cropW.toDouble(), cropH.toDouble()));
  }

  Widget _camBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── Result overlay ───────────────────────────────────────────────────────────

class _ResultOverlay extends StatelessWidget {
  final BarcodeVerification verification;
  final bool isOk;
  final VoidCallback onContinue;
  final VoidCallback onDetail;

  const _ResultOverlay({
    required this.verification,
    required this.isOk,
    required this.onContinue,
    required this.onDetail,
  });

  String get _mainReason {
    if (isOk) {
      return verification.recommendations.isNotEmpty
          ? verification.recommendations.first.title
          : '${verification.overallGrade.label} · ${verification.symbology.displayName}';
    }
    final params = verification.parameters;
    final sorted = params.allValues.toList()
      ..sort((a, b) => a.grade.numeric.compareTo(b.grade.numeric));
    final worst = sorted.first;
    return '${_paramLabel(params, worst)} · Grado ${worst.grade.letter}';
  }

  String get _rootCause {
    if (isOk) return '';
    final params = verification.parameters;
    final sorted = params.allValues.toList()
      ..sort((a, b) => a.grade.numeric.compareTo(b.grade.numeric));
    return _rootCauseFor(params, sorted.first);
  }

  String _paramLabel(ISOParameters p, GradeValue v) {
    if (identical(v, p.symbolContrast)) return 'Contraste bajo (SC)';
    if (identical(v, p.modulation)) return 'Modulación insuficiente (MOD)';
    if (identical(v, p.defects)) {
      final basis = v.estimationBasis ?? '';
      if (basis.contains('barras-rotas')) return 'Barras rotas / faltantes (DEF)';
      if (basis.contains('void')) return 'Void en barras (DEF)';
      if (basis.contains('spot')) return 'Mancha en espacios (DEF)';
      return 'Defectos de impresión (DEF)';
    }
    if (identical(v, p.decodability)) return 'No decodificable';
    if (p.minimumReflectance != null &&
        identical(v, p.minimumReflectance)) return 'Reflectancia mínima (MR)';
    if (p.edgeContrast != null && identical(v, p.edgeContrast))
      return 'Bordes difusos (EC)';
    if (p.quietZones != null && identical(v, p.quietZones)) {
      final basis = v.estimationBasis ?? '';
      return basis.contains('Contaminación')
          ? 'Manchón en zona silenciosa (QZ)'
          : 'Margen insuficiente (QZ)';
    }
    if (p.fixedPatternDamage != null &&
        identical(v, p.fixedPatternDamage)) return 'Daño en patrón fijo';
    if (p.gridNonuniformity != null &&
        identical(v, p.gridNonuniformity)) return 'No-uniformidad de rejilla';
    if (p.axialNonuniformity != null &&
        identical(v, p.axialNonuniformity)) return 'No-uniformidad axial';
    if (p.unusedErrorCorrection != null &&
        identical(v, p.unusedErrorCorrection)) return 'Corrección de error baja';
    if (p.printGrowth != null && identical(v, p.printGrowth))
      return 'Crecimiento de impresión';
    return 'Calidad insuficiente';
  }

  String _rootCauseFor(ISOParameters p, GradeValue v) {
    if (identical(v, p.symbolContrast))
      return v.grade == ISOGrade.F
          ? 'Ribbon agotado o cabezal sin tinta'
          : 'Aumentar energía del cabezal';
    if (identical(v, p.defects)) {
      final basis = v.estimationBasis ?? '';
      if (basis.contains('barras-rotas')) return 'Sección de código dañada — revisar etiqueta';
      if (basis.contains('void')) return 'Cabezal obstruido — limpiar urgente';
      if (basis.contains('spot')) return 'Temperatura alta o cabezal sucio';
      return 'Revisar cabezal de impresión';
    }
    if (p.quietZones != null && identical(v, p.quietZones)) {
      final basis = v.estimationBasis ?? '';
      return basis.contains('Contaminación')
          ? 'Manchón de tinta — revisar ribbon y presión'
          : 'Ajustar márgenes en el diseño de etiqueta';
    }
    if (p.edgeContrast != null && identical(v, p.edgeContrast))
      return 'Ribbon desgastado o velocidad de impresión alta';
    if (identical(v, p.modulation))
      return 'Calibrar presión uniforme del cabezal';
    if (p.minimumReflectance != null &&
        identical(v, p.minimumReflectance)) return 'Papel muy oscuro o contaminado';
    if (p.printGrowth != null && identical(v, p.printGrowth))
      return 'Reducir energía o temperatura del cabezal';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ok = isOk;
    final grade = verification.overallGrade;
    final color = ok ? AppColors.ok : AppColors.nok;
    final bg = ok ? AppColors.okBg : AppColors.nokBg;

    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: color.withOpacity(0.35), width: 2),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 4)
                        ],
                      ),
                      child: Center(
                        child: Text(
                          ok ? '✓' : '✗',
                          style: TextStyle(
                            fontSize: 44,
                            color: ok ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(grade.letter,
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'JetBrainsMono',
                          color: color,
                          height: 1,
                        )),
                    const SizedBox(height: 8),
                    Text(
                      ok ? 'OK — APROBADO' : 'NO OK — RECHAZADO',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: color.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _mainReason,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          if (_rootCause.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.build_rounded,
                                    size: 11,
                                    color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _rootCause,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${verification.symbology.displayName} · ${verification.standard}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: GestureDetector(
                      onTap: onContinue,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            '▶  Continuar',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ok ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onDetail,
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Center(
                          child: Text('🔬',
                              style: TextStyle(fontSize: 24)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
