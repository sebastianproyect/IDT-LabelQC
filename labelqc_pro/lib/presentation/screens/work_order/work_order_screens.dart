import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide BarcodeType;
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../../domain/entities/entities.dart';
import '../../../data/datasources/local/database/app_database.dart';
import '../../../services/iso/analysis_engine.dart';
import '../../../services/spc/spc_and_recommendations.dart';
import '../../../injection.dart';
import '../../../services/pdf/of_pdf_generator.dart';
import 'package:printing/printing.dart';

// ════════════════════════════════════════════
// WORK ORDER LIST (entry point)
// Immediately navigates to create screen
// ════════════════════════════════════════════

class WorkOrderListScreen extends StatelessWidget {
  const WorkOrderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Go directly to create screen on first access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.pushReplacement('/workorders/create');
    });
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }
}

// ════════════════════════════════════════════
// WORK ORDER CREATE — Step 1: OF# + Operator
// ════════════════════════════════════════════

class WorkOrderCreateScreen extends StatefulWidget {
  const WorkOrderCreateScreen({super.key});
  @override
  State<WorkOrderCreateScreen> createState() => _WorkOrderCreateScreenState();
}

class _WorkOrderCreateScreenState extends State<WorkOrderCreateScreen> {
  final _db = getIt<AppDatabase>();
  final _ofCtrl = TextEditingController();
  String? _selectedOperatorId;
  String? _selectedOperatorName;
  List<Operator> _operators = [];
  bool _isSaving = false;
  bool _scanning = false; // camera mode for OF#

  @override
  void initState() {
    super.initState();
    _loadOperators();
  }

  @override
  void dispose() {
    _ofCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOperators() async {
    final ops = await _db.getOperators();
    if (mounted) setState(() => _operators = ops);
  }

  Future<void> _scanOFNumber() async {
    setState(() => _scanning = true);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _BarcodeScanDialog(),
    );
    setState(() => _scanning = false);
    if (result != null && result.isNotEmpty) {
      _ofCtrl.text = result;
    }
  }

  Future<void> _start() async {
    final ofNum = _ofCtrl.text.trim();
    if (ofNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduce el número de OF')));
      return;
    }
    if (_selectedOperatorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un operario')));
      return;
    }

    setState(() => _isSaving = true);
    final id = const Uuid().v4();
    final wo = WorkOrder(
      id: id,
      orderNumber: ofNum,
      operatorId: _selectedOperatorId!,
      operatorName: _selectedOperatorName!,
      startDate: DateTime.now(),
      status: WorkOrderStatus.active,
      createdAt: DateTime.now(),
    );
    await _db.insertWorkOrder(wo);
    setState(() => _isSaving = false);
    if (mounted) context.go('/workorders/$id/scan');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Nueva Orden de Fabricación')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Paso 1 de 1 — Datos de la OF',
                  style: TextStyle(fontSize: 11, color: AppColors.accent,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ),
            const SizedBox(height: 24),

            // OF number field
            const Text('NÚMERO DE ORDEN DE FABRICACIÓN', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3,
              color: AppColors.textSecondary,
            )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ofCtrl,
                  style: const TextStyle(
                    fontSize: 18, fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'OF-2025-001',
                    hintStyle: TextStyle(fontSize: 18, color: AppColors.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _scanOFNumber,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      color: AppColors.accent, size: 26),
                ),
              ),
            ]),

            const SizedBox(height: 28),

            // Operator dropdown
            const Text('OPERARIO RESPONSABLE', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3,
              color: AppColors.textSecondary,
            )),
            const SizedBox(height: 8),

            if (_operators.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warn, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(child: Text(
                    'No hay operarios. Ve a Configuración > Operarios para añadir.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  )),
                  TextButton(
                    onPressed: () => context.push('/operators'),
                    child: const Text('Añadir'),
                  ),
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedOperatorId,
                    hint: const Text('Seleccionar operario',
                        style: TextStyle(color: AppColors.textMuted)),
                    dropdownColor: AppColors.surface2,
                    style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                    isExpanded: true,
                    items: _operators.map((op) => DropdownMenuItem(
                      value: op.id,
                      child: Text(op.name),
                    )).toList(),
                    onChanged: (v) {
                      final op = _operators.firstWhere((o) => o.id == v);
                      setState(() {
                        _selectedOperatorId = v;
                        _selectedOperatorName = op.name;
                      });
                    },
                  ),
                ),
              ),

            const Spacer(),

            IndustrialButton(
              label: 'Iniciar escaneo',
              icon: Icons.qr_code_scanner_rounded,
              variant: IndustrialButtonVariant.ok,
              fullWidth: true, large: true,
              isLoading: _isSaving,
              onTap: _operators.isEmpty ? null : _start,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// BARCODE SCAN DIALOG (for OF number)
// ════════════════════════════════════════════

class _BarcodeScanDialog extends StatefulWidget {
  const _BarcodeScanDialog();
  @override
  State<_BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

class _BarcodeScanDialogState extends State<_BarcodeScanDialog> {
  final _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    returnImage: false,
  );
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    final v = cap.barcodes.firstOrNull?.rawValue;
    if (v != null && v.isNotEmpty) {
      _done = true;
      Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 320,
        child: Stack(children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          const Center(
            child: SizedBox(
              width: 200, height: 100,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(color: Colors.white54, width: 1.5)),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12, right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(null),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
          const Positioned(
            bottom: 16, left: 0, right: 0,
            child: Center(child: Text('Apunta al código de la OF',
              style: TextStyle(color: Colors.white70, fontSize: 13))),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════
// WORK ORDER DETAIL (legacy — not used in new flow)
// ════════════════════════════════════════════

class WorkOrderDetailScreen extends StatelessWidget {
  final String workOrderId;
  const WorkOrderDetailScreen({super.key, required this.workOrderId});
  @override
  Widget build(BuildContext context) =>
      WorkOrderScanScreen(workOrderId: workOrderId);
}

// ════════════════════════════════════════════
// WORK ORDER SCAN SCREEN — split view
// Top: scanner  |  Bottom: scan history
// ════════════════════════════════════════════

class WorkOrderScanScreen extends StatefulWidget {
  final String workOrderId;
  final String? checkpointId;
  const WorkOrderScanScreen({super.key, required this.workOrderId, this.checkpointId});
  @override
  State<WorkOrderScanScreen> createState() => _WorkOrderScanScreenState();
}

class _WorkOrderScanScreenState extends State<WorkOrderScanScreen> {
  final _db = getIt<AppDatabase>();
  final _engine = getIt<BarcodeAnalysisEngine>();
  final _recEngine = getIt<RecommendationEngine>();

  late final MobileScannerController _scanner;
  bool _torchOn = false;
  bool _isAnalyzing = false;
  String? _lastScannedId;
  Timer? _debounceTimer;
  BarcodeCapture? _pendingCapture;

  Map<String, dynamic>? _workOrder;
  List<BarcodeVerification> _history = [];
  PrintSystem _printSystem = PrintSystem.ttr;
  ISOGrade _minGrade = ISOGrade.C;

  // Scan zone: center band, full width, 30% of preview height
  static const _scanWindowFraction = 0.30;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: [BarcodeFormat.all],
      returnImage: true,
    );
    _loadData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final wo = await _db.getWorkOrderById(widget.workOrderId);
    final settings = await _db.getAllSettings();
    final ps = PrintSystem.fromName(settings['print_system'] ?? 'ttr');
    final mg = ISOGrade.fromLetter(settings['min_acceptable_grade'] ?? 'C');
    final rows = await _db.getVerificationsForWorkOrder(widget.workOrderId);
    final history = rows.map((r) {
      final params = ISOParameters.fromJson(jsonDecode(r['parameters_json'] as String));
      return BarcodeVerification(
        id: r['id'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(r['timestamp'] as int),
        symbology: BarcodeType.values.firstWhere(
          (t) => t.name == r['symbology'], orElse: () => BarcodeType.code128),
        decodedValue: r['decoded_value'] as String,
        standard: r['standard'] as String,
        parameters: params,
        overallGrade: ISOGrade.fromLetter(r['overall_grade'] as String),
        captureMode: OperatorMode.workOrder,
        workOrderId: widget.workOrderId,
      );
    }).toList();
    if (mounted) {
      setState(() {
        _workOrder = wo;
        _printSystem = ps;
        _minGrade = mg;
        _history = history;
      });
    }
  }

  bool _isAcceptable(ISOGrade grade) => grade.numeric >= _minGrade.numeric;

  void _onDetect(BarcodeCapture capture) {
    if (_isAnalyzing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    // Deduplicate: skip same value within 3 seconds
    final newId = '${barcode.rawValue}_${DateTime.now().millisecondsSinceEpoch ~/ 3000}';
    if (newId == _lastScannedId) return;
    _lastScannedId = newId;

    _pendingCapture = capture;
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: 300), _analyzeCapture);
  }

  Future<void> _analyzeCapture() async {
    final capture = _pendingCapture;
    if (capture == null || _isAnalyzing || !mounted) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final type = _mapFormat(barcode.format);

      final result = _engine.analyze(
        rawBytes: capture.image,
        captureSize: capture.size,
        corners: barcode.corners,
        rawValue: barcode.rawValue,
        symbology: type,
      );

      if (result.isRepetir) {
        // Frame no analizable: continúa escaneando automáticamente.
        if (mounted) setState(() => _isAnalyzing = false);
        return;
      }

      final params = result.parameters!;
      final grade = result.overallGrade!;
      final recs = _recEngine.generate(
        verification: BarcodeVerification(
          id: '', timestamp: DateTime.now(), symbology: type,
          decodedValue: barcode.rawValue!, standard: type.standard,
          parameters: params, overallGrade: grade,
          captureMode: OperatorMode.workOrder,
        ),
        printSystem: _printSystem,
      );
      final v = BarcodeVerification(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        symbology: type,
        decodedValue: barcode.rawValue!,
        standard: type.standard,
        parameters: params,
        overallGrade: grade,
        capturedImage: capture.image,
        captureMode: OperatorMode.workOrder,
        workOrderId: widget.workOrderId,
        operatorId: _workOrder?['operator_id'] as String?,
        recommendations: recs,
      );
      await _db.insertVerification(v);

      final ok = _isAcceptable(v.overallGrade);
      if (ok) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.heavyImpact();
      }

      setState(() {
        _history = [v, ..._history];
        _isAnalyzing = false;
      });
    } catch (_) {
      setState(() => _isAnalyzing = false);
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

  Future<void> _finishOF() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Finalizar OF',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'OF ${_workOrder?['order_number'] ?? ''}\n'
          '${_history.length} escaneos realizados',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'home'),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Menú principal'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.surface2),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'pdf'),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Generar PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    await _db.updateWorkOrderStatus(widget.workOrderId, WorkOrderStatus.completed);

    if (choice == 'pdf') {
      await _generatePDF();
    }

    if (mounted) context.go('/home');
  }

  Future<void> _generatePDF() async {
    if (_workOrder == null || _history.isEmpty) return;
    try {
      final ok = _history.where((v) => _isAcceptable(v.overallGrade)).length;
      final bytes = await OFPdfGenerator.generate(
        workOrder: _workOrder!,
        history: _history.reversed.toList(),
        printSystem: _printSystem,
        minGrade: _minGrade,
        okCount: ok,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'OF_${_workOrder!['order_number']}_informe.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ofNumber = _workOrder?['order_number'] as String? ?? '—';
    final operatorName = _workOrder?['operator_name'] as String? ?? '—';
    final total = _history.length;
    final okCount = _history.where((v) => _isAcceptable(v.overallGrade)).length;
    final nokCount = total - okCount;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── TOP: CAMERA ──────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                ),

                // Scan zone overlay — highlighted central band
                Positioned.fill(
                  child: LayoutBuilder(builder: (_, constraints) {
                    final h = constraints.maxHeight;
                    final zoneH = h * _scanWindowFraction;
                    final zoneTop = (h - zoneH) / 2;
                    return Stack(children: [
                      // Dark zones above and below
                      Positioned(top: 0, left: 0, right: 0, height: zoneTop,
                          child: Container(color: Colors.black.withOpacity(0.55))),
                      Positioned(bottom: 0, left: 0, right: 0, height: zoneTop,
                          child: Container(color: Colors.black.withOpacity(0.55))),
                      // Scan zone border
                      Positioned(
                        top: zoneTop, left: 16, right: 16, height: zoneH,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accent.withOpacity(0.8), width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      // Animated corners
                      Positioned(top: zoneTop + 8, left: 24, child: _Corner()),
                      Positioned(top: zoneTop + 8, right: 24, child: _Corner(flipH: true)),
                      Positioned(bottom: zoneTop + 8, left: 24, child: _Corner(flipV: true)),
                      Positioned(bottom: zoneTop + 8, right: 24, child: _Corner(flipH: true, flipV: true)),
                    ]);
                  }),
                ),

                // Top bar
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      _camBtn(Icons.arrow_back_rounded, () => context.pop()),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('OF: $ofNumber', style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                fontFamily: 'JetBrainsMono', color: Colors.white,
                              )),
                              Text(operatorName, style: TextStyle(
                                fontSize: 11, color: Colors.white.withOpacity(0.7),
                              )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _camBtn(
                        _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        () { _scanner.toggleTorch(); setState(() => _torchOn = !_torchOn); },
                      ),
                    ]),
                  ),
                ),

                // Stats overlay bottom of camera
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.black54,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('Total', total.toString(), Colors.white),
                        _stat('OK', okCount.toString(), AppColors.ok),
                        _stat('NOK', nokCount.toString(), AppColors.nok),
                        _stat('Mín.', 'Grado ${_minGrade.letter}',
                            AppColors.warn),
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
                        child: CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── BOTTOM: HISTORY ───────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.bg,
              child: Column(
                children: [
                  // History header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      const Text('HISTORIAL DE ESCANEOS', style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 1.3, color: AppColors.textSecondary,
                      )),
                      const Spacer(),
                      GestureDetector(
                        onTap: _finishOF,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_rounded, color: Colors.black, size: 16),
                            SizedBox(width: 6),
                            Text('Finalizar OF', style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black,
                            )),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: _history.isEmpty
                        ? const Center(child: Text(
                            'Escanea el primer código de barras',
                            style: TextStyle(fontSize: 13,
                                color: AppColors.textMuted),
                          ))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _history.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) => _HistoryTile(
                              v: _history[i],
                              isAcceptable: _isAcceptable(_history[i].overallGrade),
                            ),
                          ),
                  ),
                ],
              ),
            ),
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
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _stat(String label, String value, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
          color: color, fontFamily: 'JetBrainsMono')),
      Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.8),
          letterSpacing: 0.8)),
    ],
  );
}

// ─── Corner decoration for scan zone ─────────────────────────────────────────
class _Corner extends StatelessWidget {
  final bool flipH, flipV;
  const _Corner({this.flipH = false, this.flipV = false});
  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flipH ? -1 : 1,
      scaleY: flipV ? -1 : 1,
      child: SizedBox(width: 20, height: 20,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }
  @override
  bool shouldRepaint(_) => false;
}

// ─── History tile ─────────────────────────────────────────────────────────────
class _HistoryTile extends StatelessWidget {
  final BarcodeVerification v;
  final bool isAcceptable;
  const _HistoryTile({required this.v, required this.isAcceptable});

  @override
  Widget build(BuildContext context) {
    final color = isAcceptable ? AppColors.ok : AppColors.nok;
    final bg = isAcceptable ? AppColors.okBg : AppColors.nokBg;
    final time = '${v.timestamp.hour.toString().padLeft(2,'0')}'
        ':${v.timestamp.minute.toString().padLeft(2,'0')}'
        ':${v.timestamp.second.toString().padLeft(2,'0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          child: Center(child: Text(v.overallGrade.letter, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900, color: color == AppColors.ok ? Colors.black : Colors.white,
            fontFamily: 'JetBrainsMono',
          ))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v.decodedValue.length > 28
              ? '${v.decodedValue.substring(0, 28)}…' : v.decodedValue,
            style: const TextStyle(fontSize: 12, fontFamily: 'JetBrainsMono',
                color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          Text('${v.symbology.displayName} · SC ${v.parameters.symbolContrast.formattedValue}',
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(isAcceptable ? 'OK' : 'NOK', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: 1,
          )),
          Text(time, style: const TextStyle(
            fontSize: 10, color: AppColors.textMuted, fontFamily: 'JetBrainsMono',
          )),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════
// EMPTY STATE (legacy)
// ════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📋', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('Sin órdenes activas', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          )),
          const SizedBox(height: 24),
          IndustrialButton(label: 'Nueva OF', icon: Icons.add_rounded, onTap: onTap),
        ]),
      ),
    );
  }
}
