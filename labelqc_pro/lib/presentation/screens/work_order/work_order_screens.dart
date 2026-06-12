import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common/widgets.dart';
import '../../../domain/entities/entities.dart';
import '../../../data/datasources/local/database/app_database.dart';
import '../../../injection.dart';
import '../production/production_scan_screen.dart';
import 'package:uuid/uuid.dart';

// ════════════════════════════════════════════
// WORK ORDER LIST
// ════════════════════════════════════════════

class WorkOrderListScreen extends StatelessWidget {
  const WorkOrderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = getIt<AppDatabase>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Órdenes de Fabricación'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/workorders/create'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getActiveWorkOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return _EmptyState(onTap: () => context.push('/workorders/create'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _WorkOrderTile(order: orders[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/workorders/create'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva OF', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _WorkOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  const _WorkOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'active';
    final isActive = status == 'active';
    final statusColor = isActive ? AppColors.ok : AppColors.textMuted;

    return GestureDetector(
      onTap: () => context.push('/workorders/${order['id']}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: isActive
                    ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 6, spreadRadius: 2)]
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order['order_number'] ?? '', style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrainsMono', color: AppColors.textPrimary,
                  )),
                  const SizedBox(height: 3),
                  Text(
                    [order['customer_name'], order['product_name'], order['machine_name']]
                        .whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? AppColors.okBg : AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: isActive ? AppColors.ok.withOpacity(0.3) : AppColors.border),
              ),
              child: Text(
                isActive ? 'ACTIVA' : status.toUpperCase(),
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: isActive ? AppColors.ok : AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// WORK ORDER CREATE
// ════════════════════════════════════════════

class WorkOrderCreateScreen extends StatefulWidget {
  const WorkOrderCreateScreen({super.key});

  @override
  State<WorkOrderCreateScreen> createState() => _WorkOrderCreateScreenState();
}

class _WorkOrderCreateScreenState extends State<WorkOrderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _machineCtrl = TextEditingController();
  final _operatorCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  BarcodeType? _selectedSymbology;
  bool _isSaving = false;

  @override
  void dispose() {
    for (final c in [_orderNumberCtrl, _customerCtrl, _productCtrl,
      _machineCtrl, _operatorCtrl, _obsCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final db = getIt<AppDatabase>();
    final id = const Uuid().v4();
    final order = WorkOrder(
      id: id,
      orderNumber: _orderNumberCtrl.text.trim(),
      customerName: _customerCtrl.text.trim().isEmpty ? null : _customerCtrl.text.trim(),
      productName: _productCtrl.text.trim().isEmpty ? null : _productCtrl.text.trim(),
      machineName: _machineCtrl.text.trim().isEmpty ? null : _machineCtrl.text.trim(),
      operatorId: 'op-current',
      operatorName: _operatorCtrl.text.trim().isEmpty ? 'Operario' : _operatorCtrl.text.trim(),
      startDate: DateTime.now(),
      status: WorkOrderStatus.active,
      expectedSymbology: _selectedSymbology,
      createdAt: DateTime.now(),
      observations: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
    );

    await db.insertWorkOrder(order);
    setState(() => _isSaving = false);
    if (mounted) context.go('/workorders/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Nueva Orden de Fabricación')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('Número OF *', _orderNumberCtrl, hint: 'OF-2025-001',
                validator: (v) => (v?.isEmpty ?? true) ? 'Campo requerido' : null),
            _field('Cliente', _customerCtrl, hint: 'Nombre del cliente'),
            _field('Producto', _productCtrl, hint: 'Nombre o referencia'),
            _field('Máquina', _machineCtrl, hint: 'ID o nombre de máquina'),
            _field('Operario', _operatorCtrl, hint: 'Nombre del operario'),
            const SizedBox(height: 4),
            const Text('SIMBOLOGÍA ESPERADA', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
              color: AppColors.textSecondary,
            )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: BarcodeType.values.map((t) {
                final sel = _selectedSymbology == t;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSymbology = sel ? null : t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.accentDim : AppColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sel ? AppColors.accent : AppColors.border),
                    ),
                    child: Text(t.displayName, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: sel ? AppColors.accent : AppColors.textSecondary,
                    )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _field('Observaciones', _obsCtrl, hint: 'Notas opcionales', maxLines: 3),
            const SizedBox(height: 24),
            IndustrialButton(
              label: 'Crear Orden de Fabricación',
              icon: Icons.add_task_rounded,
              variant: IndustrialButtonVariant.primary,
              fullWidth: true, large: true,
              isLoading: _isSaving,
              onTap: _save,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, String? Function(String?)? validator, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2,
          color: AppColors.textSecondary,
        )),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl, maxLines: maxLines, validator: validator,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(hintText: hint),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════
// WORK ORDER DETAIL
// ════════════════════════════════════════════

class WorkOrderDetailScreen extends StatelessWidget {
  final String workOrderId;
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  Widget build(BuildContext context) {
    final db = getIt<AppDatabase>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: db.getWorkOrderById(workOrderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('Orden no encontrada',
                style: TextStyle(color: AppColors.textSecondary)));
          }
          return _DetailBody(order: order);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final Map<String, dynamic> order;
  const _DetailBody({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'active';
    final isActive = status == 'active';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: AppColors.bg,
          title: Text(order['order_number'] ?? '',
              style: const TextStyle(fontFamily: 'JetBrainsMono')),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.okBg : AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isActive ? AppColors.ok.withOpacity(0.3) : AppColors.border),
              ),
              child: Text(
                isActive ? 'EN PRODUCCIÓN' : status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: isActive ? AppColors.ok : AppColors.textSecondary,
                ),
              ),
            ),
          ],
          floating: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _InfoCard(order: order),
              const SizedBox(height: 16),
              IndustrialButton(
                label: 'Escanear ahora',
                icon: Icons.qr_code_scanner_rounded,
                variant: IndustrialButtonVariant.ok,
                fullWidth: true, large: true,
                onTap: () => context.push('/workorders/${order['id']}/scan'),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Puntos de Control'),
              const SizedBox(height: 12),
              _Timeline(),
              const SizedBox(height: 20),
              if (isActive)
                OutlinedButton.icon(
                  onPressed: () => _closeOrder(context),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Cerrar Orden de Fabricación'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warn,
                    side: BorderSide(color: AppColors.warn.withOpacity(0.4)),
                    minimumSize: const Size(double.infinity, 52),
                  ),
                ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }

  void _closeOrder(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar Orden'),
        content: Text('¿Cerrar la OF ${order['order_number']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar OF')),
        ],
      ),
    );
    if (confirm == true) {
      await getIt<AppDatabase>().updateWorkOrderStatus(order['id'], WorkOrderStatus.completed);
      if (context.mounted) context.pop();
    }
  }
}

class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _InfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    String fmtDate(int? ms) {
      if (ms == null) return '—';
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} '
             '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        _Row('Cliente', order['customer_name'] ?? '—'),
        _Row('Producto', order['product_name'] ?? '—'),
        _Row('Máquina', order['machine_name'] ?? '—'),
        _Row('Operario', order['operator_name'] ?? '—'),
        _Row('Simbología', order['expected_symbology'] ?? 'Auto'),
        _Row('Inicio', fmtDate(order['start_date'] as int?)),
      ]),
    );
  }

  Widget _Row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(
        fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600,
      ))),
      Expanded(child: Text(value, style: const TextStyle(
        fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500,
      ))),
    ]),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    final checkpoints = CheckpointType.values.take(5).toList();
    return Column(
      children: checkpoints.asMap().entries.map((entry) {
        final i = entry.key;
        final cp = entry.value;
        final isDone = i == 0;
        final isActive = i == 1;

        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.okBg : isActive ? AppColors.accentDim : AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? AppColors.ok : isActive ? AppColors.accent : AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: Center(child: Text(
                  isDone ? '✓' : isActive ? '▶' : '○',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: isDone ? AppColors.ok : isActive ? AppColors.accent : AppColors.textMuted,
                  ),
                )),
              ),
              if (i < checkpoints.length - 1)
                Expanded(child: Container(width: 1,
                    color: isDone ? AppColors.ok.withOpacity(0.3) : AppColors.border)),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cp.displayName, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.accent : AppColors.textPrimary,
                  )),
                  if (isDone) const Text('Completado', style: TextStyle(
                    fontSize: 11, color: AppColors.ok)),
                  if (isActive) const Text('En curso', style: TextStyle(
                    fontSize: 11, color: AppColors.accent)),
                ]),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════
// WORK ORDER SCAN SCREEN
// ════════════════════════════════════════════

class WorkOrderScanScreen extends StatelessWidget {
  final String workOrderId;
  final String? checkpointId;
  const WorkOrderScanScreen({super.key, required this.workOrderId, this.checkpointId});

  @override
  Widget build(BuildContext context) => const ProductionScanScreen();
}

// ════════════════════════════════════════════
// EMPTY STATE
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
          const Text('Sin órdenes de fabricación', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          )),
          const SizedBox(height: 8),
          const Text(
            'Crea una OF para gestionar la calidad de tu producción.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          IndustrialButton(label: 'Crear primera OF', icon: Icons.add_rounded, onTap: onTap),
        ]),
      ),
    );
  }
}
