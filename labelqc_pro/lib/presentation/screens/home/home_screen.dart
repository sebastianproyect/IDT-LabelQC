import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Seleccionar modo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ModeCard(
                    icon: '⚡',
                    label: 'PRODUCCIÓN',
                    description: 'Verificación rápida para operarios. Respuesta inmediata en verde o rojo.',
                    badge: 'Operario',
                    accentColor: AppColors.ok,
                    onTap: () => context.push('/production'),
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    icon: '🔬',
                    label: 'TÉCNICO',
                    description: 'Análisis completo ISO con todos los parámetros y recomendaciones.',
                    badge: 'Calidad',
                    accentColor: AppColors.accent,
                    onTap: () => context.push('/technical'),
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    icon: '📋',
                    label: 'ORDEN DE FABRICACIÓN',
                    description: 'Gestión completa de producción con trazabilidad, patrón maestro e informes.',
                    badge: 'Responsable',
                    accentColor: AppColors.warn,
                    onTap: () => context.push('/workorders'),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(child: _StatsStrip()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverToBoxAdapter(child: _QuickActions()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('QC', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black,
              fontFamily: 'JetBrainsMono',
            )),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LabelQC Pro', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
            )),
            Text('Verificación ISO · v1.0', style: TextStyle(
              fontSize: 11, color: AppColors.textSecondary, letterSpacing: 0.5,
            )),
          ],
        ),
        const Spacer(),
        _IconBtn(icon: Icons.bar_chart_rounded, onTap: () => context.push('/dashboard')),
        const SizedBox(width: 8),
        _IconBtn(icon: Icons.settings_rounded, onTap: () => context.push('/settings')),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 18),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String icon, label, description, badge;
  final Color accentColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon, required this.label, required this.description,
    required this.badge, required this.accentColor, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: Text(icon, style: const TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary, letterSpacing: 0.5,
                        )),
                        const SizedBox(height: 4),
                        Text(description, style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary, height: 1.4,
                        )),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: accentColor.withOpacity(0.25)),
                          ),
                          child: Text(badge, style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: accentColor, letterSpacing: 0.8,
                          )),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _StatItem('147', 'HOY', AppColors.accent),
          _divider(),
          _StatItem('B+', 'MEDIA', AppColors.gradeB),
          _divider(),
          _StatItem('3', 'NOK', AppColors.warn),
          _divider(),
          _StatItem('2', 'OFs ACTIVAS', AppColors.ok),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: AppColors.border);
}

class _StatItem extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatItem(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(value, style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900,
              fontFamily: 'JetBrainsMono', color: color,
            )),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(
              fontSize: 9, color: AppColors.textSecondary,
              letterSpacing: 1.0, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ACCIONES RÁPIDAS', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
          color: AppColors.textSecondary,
        )),
        const SizedBox(height: 10),
        Row(
          children: [
            _QuickBtn('⭐', 'Patrones', () => context.push('/patterns')),
            const SizedBox(width: 10),
            _QuickBtn('📊', 'Dashboard', () => context.push('/dashboard')),
            const SizedBox(width: 10),
            _QuickBtn('⚙️', 'Ajustes', () => context.push('/settings')),
          ],
        ),
      ],
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String emoji, label;
  final VoidCallback onTap;
  const _QuickBtn(this.emoji, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
              )),
            ],
          ),
        ),
      ),
    );
  }
}
