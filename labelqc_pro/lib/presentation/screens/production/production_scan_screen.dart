import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../../domain/entities/entities.dart';
import '../../../services/iso/iso_analyzers.dart';
import '../../../services/spc/spc_and_recommendations.dart';
import 'dart:typed_data';

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
    formats: BarcodeFormat.all,
  );

  bool _torchOn = false;
  bool _isAnalyzing = false;
  bool _showResult = false;
  BarcodeVerification? _lastResult;

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
  }

  @override
  void dispose() {
    _scanner.dispose();
    _resultAnim.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isAnalyzing || _showResult) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final imageBytes = capture.image;
      final type = _mapFormat(barcode.format);
      
      ISOParameters params;
      if (type.is2D) {
        params = _analyzer2D.analyze(
          imageBytes: imageBytes ?? Uint8List(0),
          symbology: type,
          decodedValue: barcode.rawValue!,
        );
      } else {
        params = _analyzer1D.analyze(
          imageBytes: imageBytes ?? Uint8List(0),
          symbology: type,
        );
      }

      final recs = _recEngine.generate(verification: BarcodeVerification(
        id: '', timestamp: DateTime.now(), symbology: type,
        decodedValue: barcode.rawValue!, standard: type.standard,
        parameters: params, overallGrade: params.overallGrade,
        captureMode: OperatorMode.production,
      ));

      final verification = BarcodeVerification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        symbology: type,
        decodedValue: barcode.rawValue!,
        standard: type.standard,
        parameters: params,
        overallGrade: params.overallGrade,
        capturedImage: imageBytes,
        captureMode: OperatorMode.production,
        recommendations: recs,
      );

      _hapticAndSound(verification.isAcceptable);

      setState(() {
        _lastResult = verification;
        _isAnalyzing = false;
        _showResult = true;
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

  void _continueScanning() {
    _resultAnim.reverse().then((_) {
      setState(() {
        _showResult = false;
        _lastResult = null;
      });
    });
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
          // Camera
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            overlayBuilder: (context, constraints) => const SizedBox.shrink(),
          ),

          // Scan overlay
          if (!_showResult)
            const Positioned.fill(child: ScanOverlay(isActive: true)),

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

          // Hint text
          if (!_showResult && !_isAnalyzing)
            Positioned(
              bottom: 60,
              left: 0, right: 0,
              child: Center(
                child: Text(
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
  final VoidCallback onContinue;
  final VoidCallback onDetail;

  const _ResultOverlay({
    required this.verification,
    required this.onContinue,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final ok = verification.isAcceptable;
    final grade = verification.overallGrade;
    final color = ok ? AppColors.ok : AppColors.nok;
    final bg = ok ? AppColors.okBg : AppColors.nokBg;
    final borderColor = color.withOpacity(0.35);

    final mainReason = verification.recommendations.isNotEmpty
        ? verification.recommendations.first.title
        : (ok ? '${grade.label} · ${verification.symbology.displayName}' : 'Calidad insuficiente');

    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Result card
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
                      child: Text(
                        mainReason,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary, height: 1.4,
                        ),
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

              // Action buttons
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
