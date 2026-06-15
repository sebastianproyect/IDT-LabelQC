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
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.all],
    returnImage: true,
  );

  bool _torchOn = false;
  bool _isAnalyzing = false;
  bool _showResult = false;
  bool _lastWasBlurry = false;
  BarcodeVerification? _lastResult;
  ISOGrade _minGrade = ISOGrade.C;

  late AnimationController _resultAnim;
  late Animation<double> _resultScale;

  final ISO15415Analyzer _analyzer2D = ISO15415Analyzer();
  final ISO15416Analyzer _analyzer1D = ISO15416Analyzer();
  final RecommendationEngine _recEngine = RecommendationEngine();

  @override
  void initState() {
    super.initState();
    _resultAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _resultScale = CurvedAnimation(parent: _resultAnim, curve: Curves.elasticOut);
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
    super.dispose();
  }

  // Rejects detections that are too small or outside the scan zone.
  // Prevents triggering on background barcodes, logos, or shelf labels nearby.
  bool _isValidDetection(BarcodeCapture capture, Barcode barcode) {
    final bb = _cornersToRect(barcode.corners);
    if (bb == null) return true;

    final frameW = capture.size.width;
    final frameH = capture.size.height;
    if (frameW <= 0 || frameH <= 0) return true;

    // Barcode must occupy at least 20% of frame width.
    // Background barcodes or accidental reads are typically much smaller.
    if (bb.width < frameW * 0.20) return false;

    // Barcode center must be within the central 60% of frame height.
    // This matches the visual scan zone (30% height centered at 50%).
    final centerY = bb.center.dy;
    if (centerY < frameH * 0.20 || centerY > frameH * 0.80) return false;

    return true;
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isAnalyzing || _showResult) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    // Smart filter: skip barcodes too small or outside the scan zone
    if (!_isValidDetection(capture, barcode)) return;

    // Sharpness check: if the image is blurry the photometric analysis is
    // unreliable. Show a warning and skip this frame instead of giving a
    // misleading grade.
    final bbox = _cornersToRect(barcode.corners);
    if (!_isSharpEnough(capture.image, capture.size, bbox)) {
      if (mounted) setState(() => _lastWasBlurry = true);
      return;
    }
    if (mounted) setState(() => _lastWasBlurry = false);

    setState(() => _isAnalyzing = true);

    try {
      final type = _mapFormat(barcode.format);
      final input = BarcodeAnalysisInput(
        rawValue: barcode.rawValue,
        symbology: type,
        corners: barcode.corners,
        boundingBox: _cornersToRect(barcode.corners),
        captureSize: capture.size,
        imageBytes: capture.image,
      );

      final params = type.is2D
          ? _analyzer2D.analyze(input)
          : _analyzer1D.analyze(input);

      // Safety floor only when the camera gave NO image bytes.
      // With image bytes (NV21), the photometric analysis is real — trust it.
      // Without image bytes we have no signal besides decodability, so a
      // decoded code is conservatively floored at Grade C.
      final rawGrade = params.overallGrade;
      final effectiveGrade = (input.imageBytes == null && rawGrade.numeric < ISOGrade.C.numeric)
          ? ISOGrade.C
          : rawGrade;

      final recs = _recEngine.generate(verification: BarcodeVerification(
        id: '', timestamp: DateTime.now(), symbology: type,
        decodedValue: barcode.rawValue!, standard: type.standard,
        parameters: params, overallGrade: effectiveGrade,
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
      _hapticAndSound(isOk);

      setState(() {
        _lastResult = verification;
        _isAnalyzing = false;
        _showResult = true;
        _lastWasBlurry = false;
      });
      _resultAnim.forward(from: 0);

    } catch (e) {
      setState(() => _isAnalyzing = false);
    }
  }

  void _hapticAndSound(bool ok) {
    if (ok) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  // Returns false when the NV21 image is too blurry for reliable photometric
  // analysis. Measures the steepness of the sharpest edge in the barcode row:
  // a focused barcode has edges that jump ≥ 18% of the total range in one pixel.
  bool _isSharpEnough(Uint8List? bytes, Size captureSize, Rect? bbox) {
    if (bytes == null) return true; // no image → can't judge, allow
    final W = captureSize.width.round();
    final H = captureSize.height.round();
    if (W <= 0 || H <= 0 || bytes.length < W * H) return true;
    // JPEG: skip sharpness check (can't read raw pixels)
    if (bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;

    // Use barcode center row; fall back to frame center
    final y = bbox != null
        ? ((bbox.top + bbox.bottom) / 2).round().clamp(1, H - 2)
        : H ~/ 2;
    final x0 = bbox != null ? bbox.left.toInt().clamp(0, W - 1) : W ~/ 4;
    final x1 = bbox != null ? bbox.right.toInt().clamp(x0 + 1, W) : 3 * W ~/ 4;
    if (x1 - x0 < 10) return true;

    int lo = 255, hi = 0;
    for (int x = x0; x < x1; x++) {
      final v = bytes[y * W + x];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    if (range < 30) return true; // uniform row → no barcode here, can't judge

    double maxGrad = 0;
    for (int x = x0 + 1; x < x1; x++) {
      final grad = (bytes[y * W + x] - bytes[y * W + x - 1]).abs().toDouble();
      if (grad > maxGrad) maxGrad = grad;
    }
    // Sharp barcode: steepest edge ≥ 18% of total range per pixel.
    return maxGrad / range >= 0.18;
  }

  void _continueScanning() {
    _resultAnim.reverse().then((_) {
      setState(() {
        _showResult = false;
        _lastResult = null;
      });
    });
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            overlayBuilder: (context, constraints) => const SizedBox.shrink(),
          ),

          // Scan zone — central 30% of height
          if (!_showResult)
            Positioned.fill(
              child: LayoutBuilder(builder: (_, constraints) {
                final h = constraints.maxHeight;
                final zoneH = h * 0.30;
                final zoneTop = (h - zoneH) / 2;
                return Stack(children: [
                  Positioned(top: 0, left: 0, right: 0, height: zoneTop,
                    child: Container(color: Colors.black.withOpacity(0.55))),
                  Positioned(bottom: 0, left: 0, right: 0, height: zoneTop,
                    child: Container(color: Colors.black.withOpacity(0.55))),
                  Positioned(top: zoneTop, left: 16, right: 16, height: zoneH,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0xFFFFC107), width: 1.5)),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                ]);
              }),
            ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _camBtn(Icons.arrow_back_rounded, () => context.pop()),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.ok.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        const Text('PRODUCCIÓN', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.ok, letterSpacing: 1.2,
                        )),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _camBtn(
                    _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
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
                      CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('Analizando...', style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ),
              ),
            ),

          // Hint / blur warning
          if (!_showResult && !_isAnalyzing)
            Positioned(
              bottom: 60,
              left: 24, right: 24,
              child: Center(
                child: _lastWasBlurry
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.6)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.center_focus_weak_rounded,
                                color: Color(0xFFFFC107), size: 14),
                            SizedBox(width: 6),
                            Text('Imagen borrosa · Acerque el teléfono',
                                style: TextStyle(
                                  color: Color(0xFFFFC107), fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      )
                    : Text(
                        'Apunta al código · Detección automática',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12, letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),

          // Result overlay
          if (_showResult && _lastResult != null)
            Positioned.fill(
              child: ScaleTransition(
                scale: _resultScale,
                child: _ResultOverlay(
                  verification: _lastResult!,
                  isOk: _lastResult!.overallGrade.numeric >= _minGrade.numeric,
                  onContinue: _continueScanning,
                  onDetail: () {
                    _continueScanning();
                    context.push('/technical/result', extra: _lastResult);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _camBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

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
    final worst = sorted.first;
    return _rootCauseFor(params, worst);
  }

  String _paramLabel(ISOParameters p, GradeValue v) {
    if (identical(v, p.symbolContrast)) return 'Contraste bajo (SC)';
    if (identical(v, p.modulation)) return 'Modulación insuficiente (MOD)';
    if (identical(v, p.defects)) {
      final basis = v.estimationBasis ?? '';
      if (basis.contains('void')) return 'Void en barras (DEF)';
      if (basis.contains('spot')) return 'Mancha en espacios (DEF)';
      return 'Defectos de impresión (DEF)';
    }
    if (identical(v, p.decodability)) return 'No decodificable';
    if (p.minimumReflectance != null && identical(v, p.minimumReflectance)) return 'Reflectancia mínima (MR)';
    if (p.edgeContrast != null && identical(v, p.edgeContrast)) return 'Bordes difusos (EC)';
    if (p.quietZones != null && identical(v, p.quietZones)) {
      final basis = v.estimationBasis ?? '';
      return basis.contains('Contaminación')
          ? 'Manchón en zona silenciosa (QZ)'
          : 'Margen insuficiente (QZ)';
    }
    if (p.fixedPatternDamage != null && identical(v, p.fixedPatternDamage)) return 'Daño en patrón fijo';
    if (p.gridNonuniformity != null && identical(v, p.gridNonuniformity)) return 'No-uniformidad de rejilla';
    if (p.axialNonuniformity != null && identical(v, p.axialNonuniformity)) return 'No-uniformidad axial';
    if (p.unusedErrorCorrection != null && identical(v, p.unusedErrorCorrection)) return 'Corrección de error baja';
    if (p.printGrowth != null && identical(v, p.printGrowth)) return 'Crecimiento de impresión';
    return 'Calidad insuficiente';
  }

  String _rootCauseFor(ISOParameters p, GradeValue v) {
    if (identical(v, p.symbolContrast)) {
      return v.grade == ISOGrade.F
          ? 'Ribbon agotado o cabezal sin tinta'
          : 'Aumentar energía del cabezal';
    }
    if (identical(v, p.defects)) {
      final basis = v.estimationBasis ?? '';
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
    if (p.edgeContrast != null && identical(v, p.edgeContrast)) {
      return 'Ribbon desgastado o velocidad de impresión alta';
    }
    if (identical(v, p.modulation)) {
      return 'Calibrar presión uniforme del cabezal';
    }
    if (p.minimumReflectance != null && identical(v, p.minimumReflectance)) {
      return 'Papel muy oscuro o contaminado';
    }
    if (p.printGrowth != null && identical(v, p.printGrowth)) {
      return 'Reducir energía o temperatura del cabezal';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ok = isOk;
    final grade = verification.overallGrade;
    final color = ok ? AppColors.ok : AppColors.nok;
    final bg = ok ? AppColors.okBg : AppColors.nokBg;
    final borderColor = color.withOpacity(0.35);

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
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, spreadRadius: 4)],
                      ),
                      child: Center(
                        child: Text(
                          ok ? '✓' : '✗',
                          style: TextStyle(
                            fontSize: 44, color: ok ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      grade.letter,
                      style: TextStyle(
                        fontSize: 72, fontWeight: FontWeight.w900,
                        fontFamily: 'JetBrainsMono', color: color, height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ok ? 'OK — APROBADO' : 'NO OK — RECHAZADO',
                      style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        color: color, letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _mainReason,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary, height: 1.4,
                            ),
                          ),
                          if (_rootCause.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.build_rounded,
                                    size: 11, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  _rootCause,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted,
                                    fontStyle: FontStyle.italic,
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
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                              fontSize: 17, fontWeight: FontWeight.w800,
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
                          child: Text('🔬', style: TextStyle(fontSize: 24)),
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
