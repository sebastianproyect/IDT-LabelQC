import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common/widgets.dart';
import '../../domain/entities/entities.dart';
import '../../data/datasources/local/database/app_database.dart';
import '../../injection.dart';

// ════════════════════════════════════════════
// MASTER PATTERN LIST
// ════════════════════════════════════════════

class PatternListScreen extends StatelessWidget {
  const PatternListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = getIt<AppDatabase>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Patrones Maestros'),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded),
              onPressed: () => context.push('/patterns/create')),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getAllPatterns(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final patterns = snapshot.data ?? [];
          if (patterns.isEmpty) {
            return _EmptyPatterns(onTap: () => context.push('/patterns/create'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: patterns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _PatternTile(pattern: patterns[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/patterns/create'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.star_rounded),
        label: const Text('Nuevo Patrón', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  final Map<String, dynamic> pattern;
  const _PatternTile({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final gradeStr = pattern['overall_grade'] as String? ?? 'C';
    final grade = ISOGrade.fromLetter(gradeStr);
    return GestureDetector(
      onTap: () => context.push('/patterns/${pattern['id']}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface3, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(child: Text('▦', style: TextStyle(fontSize: 22, color: AppColors.textMuted))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pattern['job_reference'] ?? '', style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
              )),
              const SizedBox(height: 3),
              Text(pattern['symbology'] ?? '', style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary,
              )),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentDim, borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                ),
                child: Text(
                  (pattern['decoded_value'] as String? ?? '').length > 28
                      ? '${(pattern['decoded_value'] as String).substring(0, 28)}…'
                      : (pattern['decoded_value'] as String? ?? ''),
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.accent,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          GradeBadge(grade: grade, size: 40),
        ]),
      ),
    );
  }
}

class _EmptyPatterns extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyPatterns({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⭐', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('Sin patrones maestros', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          )),
          const SizedBox(height: 8),
          const Text(
            'Crea un patrón maestro (Golden Sample) como referencia de calidad.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          IndustrialButton(label: 'Crear patrón maestro', icon: Icons.star_rounded, onTap: onTap),
        ]),
      ),
    );
  }
}

class PatternCreateScreen extends StatelessWidget {
  const PatternCreateScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Nuevo Patrón Maestro')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⭐', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          const Text('Escanea la etiqueta de referencia',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text('Solo se aceptan muestras con calificación A o B como patrón maestro.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          IndustrialButton(
            label: 'Ir a escanear',
            icon: Icons.qr_code_scanner_rounded,
            variant: IndustrialButtonVariant.primary,
            fullWidth: true,
            onTap: () => context.push('/technical'),
          ),
        ]),
      ),
    ),
  );
}

class PatternDetailScreen extends StatelessWidget {
  final String patternId;
  const PatternDetailScreen({super.key, required this.patternId});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Detalle Patrón')),
    body: Center(child: Text('Patrón: $patternId',
        style: const TextStyle(color: AppColors.textSecondary))),
  );
}

// ════════════════════════════════════════════
// DASHBOARD SCREEN
// ════════════════════════════════════════════

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = getIt<AppDatabase>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(_monthLabel(), style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: db.getDashboardStats(),
        builder: (ctx, snap) {
          final stats = snap.data ?? {
            'total': 0, 'gradeA': 0, 'gradeB': 0, 'gradeC': 0,
            'gradeD': 0, 'gradeF': 0, 'mean': 0.0, 'okRate': 0.0,
          };
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: db.getGradeTrend(),
            builder: (ctx2, trendSnap) {
              final trend = trendSnap.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _KPIGrid(stats: stats),
                  const SizedBox(height: 16),
                  _TrendChart(trend: trend),
                  const SizedBox(height: 16),
                  _GradeDistribution(stats: stats),
                  const SizedBox(height: 32),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _monthLabel() {
    final now = DateTime.now();
    const months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return '${months[now.month - 1]} ${now.year}';
  }
}

class _KPIGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _KPIGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final mean = (stats['mean'] as num?)?.toDouble() ?? 0;
    final meanGrade = ISOGrade.fromNumeric(mean);
    final okRate = (stats['okRate'] as num?)?.toDouble() ?? 0;
    return GridView.count(
      crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10,
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: [
        _KPI('${stats['total'] ?? 0}', 'TOTAL', AppColors.accent),
        _KPI(meanGrade.letter, 'MEDIA', AppColors.forGrade(meanGrade.letter)),
        _KPI('${(okRate * 100).toStringAsFixed(0)}%', 'TASA OK', AppColors.ok),
        _KPI('${stats['gradeA'] ?? 0}', 'Grado A', AppColors.gradeA),
        _KPI('${stats['gradeB'] ?? 0}', 'Grado B', AppColors.gradeB),
        _KPI('${stats['gradeC'] ?? 0}', 'Grado C', AppColors.gradeC),
        _KPI('${stats['gradeD'] ?? 0}', 'Grado D', AppColors.gradeD),
        _KPI('${stats['gradeF'] ?? 0}', 'Grado F', AppColors.gradeF),
        _KPI('0', 'OFs MES', AppColors.warn),
      ],
    );
  }
}

class _KPI extends StatelessWidget {
  final String value, label;
  final Color color;
  const _KPI(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w900,
          fontFamily: 'JetBrainsMono', color: color, height: 1,
        )),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(
          fontSize: 9, color: AppColors.textSecondary,
          letterSpacing: 0.8, fontWeight: FontWeight.w600,
        ), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    // Group by day and compute mean grade
    final byDay = <String, List<double>>{};
    for (final row in trend) {
      final ts = row['timestamp'] as int? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final key = '${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}';
      final g = (row['overall_grade_numeric'] as num?)?.toDouble() ?? 0;
      byDay.putIfAbsent(key, () => []).add(g);
    }
    final days = byDay.entries.toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'Tendencia de calidad — 14 días'),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: days.isEmpty
              ? const Center(child: Text('Sin datos aún',
                  style: TextStyle(color: AppColors.textMuted)))
              : BarChart(BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 4.2, minY: 0,
                  barGroups: days.asMap().entries.map((e) {
                    final mean = e.value.value.reduce((a, b) => a + b) / e.value.value.length;
                    final grade = ISOGrade.fromNumeric(mean);
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [BarChartRodData(
                        toY: mean,
                        color: AppColors.forGrade(grade.letter),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      )],
                    );
                  }).toList(),
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false, horizontalInterval: 1,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: AppColors.border, strokeWidth: 1, dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, interval: 1, reservedSize: 24,
                      getTitlesWidget: (v, _) {
                        final labels = {1.0: 'D', 2.0: 'C', 3.0: 'B', 4.0: 'A'};
                        return Text(labels[v] ?? '', style: const TextStyle(
                          fontSize: 10, fontFamily: 'JetBrainsMono',
                          color: AppColors.textSecondary, fontWeight: FontWeight.w700,
                        ));
                      },
                    )),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                )),
        ),
      ]),
    );
  }
}

class _GradeDistribution extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _GradeDistribution({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = (stats['total'] as int?) ?? 0;
    if (total == 0) return const SizedBox.shrink();
    final entries = [
      ('A', (stats['gradeA'] as int?) ?? 0, AppColors.gradeA),
      ('B', (stats['gradeB'] as int?) ?? 0, AppColors.gradeB),
      ('C', (stats['gradeC'] as int?) ?? 0, AppColors.gradeC),
      ('D', (stats['gradeD'] as int?) ?? 0, AppColors.gradeD),
      ('F', (stats['gradeF'] as int?) ?? 0, AppColors.gradeF),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'Distribución de grados'),
        const SizedBox(height: 14),
        ...entries.map((e) {
          final fraction = total > 0 ? e.$2 / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: e.$3.withOpacity(0.15), borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: e.$3.withOpacity(0.3)),
                ),
                child: Center(child: Text(e.$1, style: TextStyle(
                  fontFamily: 'JetBrainsMono', fontSize: 12,
                  fontWeight: FontWeight.w900, color: e.$3,
                ))),
              ),
              const SizedBox(width: 10),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction, minHeight: 8,
                  backgroundColor: AppColors.surface3,
                  valueColor: AlwaysStoppedAnimation(e.$3),
                ),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 32, child: Text('${e.$2}', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                fontFamily: 'JetBrainsMono', color: e.$3,
              ), textAlign: TextAlign.right)),
            ]),
          );
        }),
      ]),
    );
  }
}

// ════════════════════════════════════════════
// SETTINGS SCREEN
// ════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = getIt<AppDatabase>();

  // Loaded from DB
  String _minGrade = 'C';
  String _printSystem = 'ttr';
  bool _vibration = true, _sounds = true, _saveImages = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _db.getAllSettings();
    if (!mounted) return;
    setState(() {
      _minGrade = s['min_acceptable_grade'] ?? 'C';
      _printSystem = s['print_system'] ?? 'ttr';
      _vibration = s['vibration'] != 'false';
      _sounds = s['sounds'] != 'false';
      _saveImages = s['save_images'] != 'false';
      _loading = false;
    });
  }

  Future<void> _save(String key, String value) async {
    await _db.setSetting(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── VERIFICACIÓN ──
          _Sec('VERIFICACIÓN', [
            _DropdownTile<String>(
              icon: Icons.grade_rounded,
              label: 'Calidad mínima aceptable',
              value: _minGrade,
              items: const ['A', 'B', 'C', 'D', 'F'],
              itemLabel: (v) => 'Grado $v',
              onChanged: (v) {
                setState(() => _minGrade = v!);
                _save('min_acceptable_grade', v!);
              },
            ),
            _Toggle(Icons.photo_camera_rounded, 'Guardar imagen en verificación',
                _saveImages, (v) {
              setState(() => _saveImages = v);
              _save('save_images', v.toString());
            }),
          ]),

          // ── SISTEMA DE IMPRESIÓN ──
          _Sec('SISTEMA DE IMPRESIÓN', [
            _DropdownTile<String>(
              icon: Icons.print_rounded,
              label: 'Sistema de impresión',
              value: _printSystem,
              items: PrintSystem.values.map((p) => p.name).toList(),
              itemLabel: (v) => PrintSystem.fromName(v).displayName,
              onChanged: (v) {
                setState(() => _printSystem = v!);
                _save('print_system', v!);
              },
            ),
          ]),

          // ── OPERARIOS ──
          _Sec('OPERARIOS', [
            _Tile(Icons.people_rounded, 'Gestión de operarios',
                value: 'Añadir / eliminar',
                onTap: () => context.push('/operators')),
          ]),

          // ── INTERFAZ ──
          _Sec('INTERFAZ', [
            _Toggle(Icons.vibration_rounded, 'Vibración al escanear',
                _vibration, (v) {
              setState(() => _vibration = v);
              _save('vibration', v.toString());
            }),
            _Toggle(Icons.volume_up_rounded, 'Sonidos',
                _sounds, (v) {
              setState(() => _sounds = v);
              _save('sounds', v.toString());
            }),
          ]),

          // ── ACERCA DE ──
          _Sec('ACERCA DE', [
            _Tile(Icons.info_rounded, 'Versión', value: '2.0.0', onTap: null),
            _Tile(Icons.description_rounded, 'Normativas',
                value: 'ISO 15416 · ISO 15415', onTap: null),
          ]),

          const SizedBox(height: 40),
          const Center(child: Text(
            'IDT LabelQC v2.0.0\n© 2025 · Verificación ISO de calidad de impresión',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.6),
          )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
// OPERATOR MANAGEMENT SCREEN
// ════════════════════════════════════════════

class OperatorManagementScreen extends StatefulWidget {
  const OperatorManagementScreen({super.key});
  @override
  State<OperatorManagementScreen> createState() => _OperatorManagementScreenState();
}

class _OperatorManagementScreenState extends State<OperatorManagementScreen> {
  final _db = getIt<AppDatabase>();
  List<Operator> _operators = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ops = await _db.getOperators();
    if (mounted) setState(() => _operators = ops);
  }

  Future<void> _addOperator() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Nuevo operario', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Nombre del operario',
            hintStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await _db.insertOperator(Operator(
        id: const Uuid().v4(),
        name: nameCtrl.text.trim(),
        createdAt: DateTime.now(),
      ));
      _load();
    }
  }

  Future<void> _deleteOperator(Operator op) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar operario', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('¿Eliminar a ${op.name}?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.nok),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteOperator(op.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Gestión de operarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: _addOperator,
            tooltip: 'Añadir operario',
          ),
        ],
      ),
      body: _operators.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('👷', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                const Text('Sin operarios', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                )),
                const SizedBox(height: 8),
                const Text('Añade operarios para asignarlos a las OF.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _addOperator,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir operario'),
                ),
              ]),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _operators.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final op = _operators[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(op.name, style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ))),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.nok, size: 20),
                      onPressed: () => _deleteOperator(op),
                    ),
                  ]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addOperator,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        child: const Icon(Icons.person_add_rounded),
      ),
    );
  }
}

// ════════════════════════════════════════════
// SETTINGS HELPER WIDGETS
// ════════════════════════════════════════════

class _Sec extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Sec(this.title, this.children);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(title, style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
            color: AppColors.textSecondary,
          )),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: children.asMap().entries.map((e) => Column(children: [
              e.value,
              if (e.key < children.length - 1)
                Container(height: 1, margin: const EdgeInsets.only(left: 52), color: AppColors.border),
            ])).toList(),
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  const _Tile(this.icon, this.label, {this.value, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
          if (value != null) Text(value!,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (onTap != null) const SizedBox(width: 6),
          if (onTap != null) const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 16),
        ]),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(this.icon, this.label, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const _DropdownTile({
    required this.icon, required this.label, required this.value,
    required this.items, required this.itemLabel, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
        DropdownButton<T>(
          value: value,
          dropdownColor: AppColors.surface2,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          underline: const SizedBox.shrink(),
          items: items.map((v) => DropdownMenuItem(
            value: v,
            child: Text(itemLabel(v)),
          )).toList(),
          onChanged: onChanged,
        ),
      ]),
    );
  }
}
