import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../../domain/entities/entities.dart';
import '../../../services/iso/iso_analyzers.dart';
import '../../../services/spc/spc_and_recommendations.dart';
import '../../../services/pdf/pdf_generator.dart';
import 'dart:typed_data';

// ════════════════════════════════════════════
// TECHNICAL SCAN SCREEN
// ════════════════════════════════════════════

class TechnicalScanScreen extends StatefulWidget {
  const TechnicalScanScreen({super.key});

  @override
  State<TechnicalScanScreen> createState() => _TechnicalScanScreenState();
}

class _TechnicalScanScreenState extends State<TechnicalScanScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.all],
    returnImage: true,
  );

  bool _torchOn = false;
  bool _isAnalyzing = false;
  final ISO15415Analyzer _analyzer2D = ISO15415Analyzer();
  final ISO15416Analyzer _analyzer1D = ISO15416Analyzer();
  final RecommendationEngine _recEngine = RecommendationEngine();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isAnalyzing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _isAnalyzing = true);
    HapticFeedback.mediumImpact();

    try {
      final imageBytes = capture.image;
      final type = _mapFormat(barcode!.format);

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

      final tempVerif = BarcodeVerification(
        id: '', timestamp: DateTime.now(), symbology: type,
        decodedValue: barcode.rawValue!, standard: type.standard,
        parameters: params, overallGrade: params.overallGrade,
        captureMode: OperatorMode.technical,
      );

      final recs = _recEngine.generate(verification: tempVerif);

      final verification = BarcodeVerification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        symbology: type,
        decodedValue: barcode.rawValue!,
        standard: type.standard,
        parameters: params,
        overallGrade: params.overallGrade,
        capturedImage: imageBytes,
        captureMode: OperatorMode.technical,
        recommendations: recs,
      );

      if (mounted) {
        setState(() => _isAnalyzing = false);
        context.push('/technical/result', extra: verification);
      }
    } catch (e) {
      if (mounted) setState(() => _isAnalyzing = false);
    }
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
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          const Positioned.fill(child: ScanOverlay(isActive: true)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _camBtn(Icons.arrow_back_rounded, () => context.pop()),
                  const SizedBox(width: 12),
                  _badge('TÉCNICO', AppColors.accent),
                  const Spacer(),
                  _camBtn(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, () {
                    _scanner.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  }),
                ],
              ),
            ),
          ),
          if (_isAnalyzing)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                    SizedBox(height: 12),
                    Text('Análisis ISO completo...', style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600,
                    )),
                  ]),
                ),
              ),
            ),
          if (!_isAnalyzing)
            const Positioned(
              bottom: 60, left: 0, right: 0,
              child: Center(child: Text(
                'Modo Técnico · Análisis ISO completo',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              )),
            ),
        ],
      ),
    );
  }

  Widget _camBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.black54, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.2)),
    ]),
  );
}

// ════════════════════════════════════════════
// TECHNICAL RESULT SCREEN
// ════════════════════════════════════════════

class TechnicalResultScreen extends StatelessWidget {
  final BarcodeVerification verification;
  const TechnicalResultScreen({super.key, required this.verification});

  @override
  Widget build(BuildContext context) {
    final grade = verification.overallGrade;
    final gradeColor = AppColors.forGrade(grade.letter);
    final p = verification.parameters;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Resultado Técnico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _sharePDF(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Image + grade header
          _HeaderCard(verification: verification),
          const SizedBox(height: 14),

          // Decoded value
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Text('▦ ', style: TextStyle(color: AppColors.accent, fontSize: 14)),
                Expanded(
                  child: Text(
                    verification.decodedValue,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 12,
                      color: AppColors.accent,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: verification.decodedValue));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copiado al portapapeles')),
                    );
                  },
                  child: const Icon(Icons.copy_rounded, size: 16, color: AppColors.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Overall result
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bgForGrade(grade.letter),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gradeColor.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('RESULTADO GLOBAL', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                    color: AppColors.textSecondary,
                  )),
                  const SizedBox(height: 2),
                  Text(verification.standard, style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted,
                  )),
                ]),
                const Spacer(),
                GradeBadge(grade: grade, size: 52, showLabel: true),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Parameters
          const SectionHeader(title: 'Parámetros ISO'),
          const SizedBox(height: 10),
          _ParametersList(params: p),
          const SizedBox(height: 20),

          // Recommendations
          if (verification.recommendations.isNotEmpty) ...[
            SectionHeader(
              title: 'Recomendaciones (${verification.recommendations.length})',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warnBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warn.withOpacity(0.3)),
                ),
                child: const Text('💡', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 10),
            ...verification.recommendations.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RecommendationCard(recommendation: r),
            )),
            const SizedBox(height: 10),
          ],

          // Action buttons
          _ActionButtons(verification: verification),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _sharePDF(BuildContext context) async {
    try {
      final generator = VerificationPdfGenerator();
      final bytes = await generator.generate(verification: verification);
      await generator.share(bytes, 'verificacion_${verification.id}.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando PDF: $e')),
      );
    }
  }
}

class _HeaderCard extends StatelessWidget {
  final BarcodeVerification verification;
  const _HeaderCard({required this.verification});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: verification.capturedImage != null
                ? ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                    child: Image.memory(verification.capturedImage!, fit: BoxFit.cover),
                  )
                : const Center(child: Text('▦', style: TextStyle(fontSize: 40, color: AppColors.textMuted))),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GradeBadge(grade: verification.overallGrade, size: 56),
                const SizedBox(height: 8),
                Text(verification.symbology.displayName, style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                )),
                Text(
                  _formatTimestamp(verification.timestamp),
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

class _ParametersList extends StatelessWidget {
  final ISOParameters params;
  const _ParametersList({required this.params});

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('Symbol Contrast', params.symbolContrast),
      ('Modulation', params.modulation),
      ('Defects', params.defects),
      ('Decodability', params.decodability),
      if (params.minimumReflectance != null) ('Min Reflectance', params.minimumReflectance!),
      if (params.edgeContrast != null) ('Edge Contrast', params.edgeContrast!),
      if (params.quietZones != null) ('Quiet Zones', params.quietZones!),
      if (params.fixedPatternDamage != null) ('Fixed Pattern Damage', params.fixedPatternDamage!),
      if (params.gridNonuniformity != null) ('Grid Nonuniformity', params.gridNonuniformity!),
      if (params.axialNonuniformity != null) ('Axial Nonuniformity', params.axialNonuniformity!),
      if (params.printGrowth != null) ('Print Growth', params.printGrowth!),
      if (params.unusedErrorCorrection != null) ('Unused Error Corr.', params.unusedErrorCorrection!),
    ];

    return Column(
      children: entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ParameterRow(name: e.$1, value: e.$2),
      )).toList(),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final BarcodeVerification verification;
  const _ActionButtons({required this.verification});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _generatePDF(context),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Generar PDF'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _saveVerification(context),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Guardar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/patterns'),
                icon: const Icon(Icons.star_rounded, size: 18),
                label: const Text('Comparar Patrón'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('Nuevo escaneo'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _generatePDF(BuildContext context) async {
    try {
      final generator = VerificationPdfGenerator();
      final bytes = await generator.generate(verification: verification);
      await generator.share(bytes, 'verificacion_${verification.id}.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _saveVerification(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verificación guardada ✓')),
    );
  }
}
