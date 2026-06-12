import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/entities.dart';

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/grade_badge.dart
// ═══════════════════════════════════════════════════════

class GradeBadge extends StatelessWidget {
  final ISOGrade grade;
  final double size;
  final bool showLabel;

  const GradeBadge({
    super.key,
    required this.grade,
    this.size = 40,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forGrade(grade.letter);
    final bg = AppColors.bgForGrade(grade.letter);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(size * 0.22),
            border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          ),
          child: Center(
            child: Text(
              grade.letter,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: size * 0.48,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            grade.label,
            style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/parameter_row.dart
// ═══════════════════════════════════════════════════════

class ParameterRow extends StatelessWidget {
  final String name;
  final GradeValue value;
  final bool compact;

  const ParameterRow({
    super.key,
    required this.name,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forGrade(value.grade.letter);
    final barFraction = _barFraction();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 8 : 11,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (value.isEstimated)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: value.estimationBasis ?? 'Valor estimado',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2400),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFF5A623).withOpacity(0.4)),
                  ),
                  child: const Text('~est.', style: TextStyle(
                    fontSize: 9, color: Color(0xFFF5A623),
                    fontWeight: FontWeight.w600, letterSpacing: 0.3,
                  )),
                ),
              ),
            ),
          Text(
            value.formattedValue,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: barFraction,
                backgroundColor: AppColors.surface3,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GradeBadge(grade: value.grade, size: compact ? 28 : 32),
        ],
      ),
    );
  }

  double _barFraction() {
    // Normalize to 0-1 based on typical ranges
    switch (value.unit) {
      case '%':
        return (value.rawMeasurement / 100).clamp(0.0, 1.0);
      case 'ratio':
        return value.rawMeasurement.clamp(0.0, 1.0);
      case 'X':
        return (value.rawMeasurement / 15).clamp(0.0, 1.0);
      default:
        return value.grade.numeric / 4.0;
    }
  }
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/industrial_button.dart
// ═══════════════════════════════════════════════════════

enum IndustrialButtonVariant { primary, ok, nok, secondary, danger }

class IndustrialButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final IndustrialButtonVariant variant;
  final bool fullWidth;
  final bool large;
  final bool isLoading;

  const IndustrialButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = IndustrialButtonVariant.primary,
    this.fullWidth = false,
    this.large = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _colors();
    final height = large ? 60.0 : 52.0;
    final fontSize = large ? 16.0 : 14.0;

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: fg.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: border != null ? Border.all(color: border) : null,
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(fg),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, color: fg, size: large ? 22 : 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, Color?) _colors() {
    switch (variant) {
      case IndustrialButtonVariant.primary:
        return (AppColors.accent, Colors.black, null);
      case IndustrialButtonVariant.ok:
        return (AppColors.ok, Colors.black, null);
      case IndustrialButtonVariant.nok:
        return (AppColors.nok, Colors.white, null);
      case IndustrialButtonVariant.secondary:
        return (AppColors.surface2, AppColors.textPrimary, AppColors.border);
      case IndustrialButtonVariant.danger:
        return (AppColors.nokBg, AppColors.nok, AppColors.nok.withOpacity(0.4));
    }
  }
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/scan_overlay.dart
// ═══════════════════════════════════════════════════════

class ScanOverlay extends StatefulWidget {
  final bool isActive;
  const ScanOverlay({super.key, this.isActive = true});

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scanLine;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scanLine = Tween<double>(begin: 0.05, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        painter: _ScanOverlayPainter(
          scanLineProgress: _scanLine.value,
          cornerOpacity: _pulse.value,
          isActive: widget.isActive,
        ),
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double scanLineProgress;
  final double cornerOpacity;
  final bool isActive;

  _ScanOverlayPainter({
    required this.scanLineProgress,
    required this.cornerOpacity,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final boxW = size.width * 0.6;
    final boxH = size.height * 0.45;
    final left = cx - boxW / 2;
    final top = cy - boxH / 2;
    final right = cx + boxW / 2;
    final bottom = cy + boxH / 2;

    // Dimming outside scan area
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final scanRect = Rect.fromLTRB(left, top, right, bottom);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final path = Path()
      ..addRect(fullRect)
      ..addRect(scanRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Scan border
    final cornerColor = isActive
        ? const Color(0xFF00C8FF).withOpacity(cornerOpacity)
        : Colors.white.withOpacity(0.3);
    final cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cLen = 24.0;
    // Top-left
    canvas.drawLine(Offset(left, top + cLen), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cLen, top), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(right - cLen, top), Offset(right, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cLen), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(right, bottom - cLen), Offset(right, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right - cLen, bottom), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(left + cLen, bottom), Offset(left, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - cLen), cornerPaint);

    // Scan line
    if (isActive) {
      final lineY = top + (bottom - top) * scanLineProgress;
      final gradient = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF00C8FF).withOpacity(0.8),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(left, lineY - 1, boxW, 2));

      final linePaint = Paint()
        ..shader = gradient
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left + 4, lineY), Offset(right - 4, lineY), linePaint);
    }
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanLineProgress != scanLineProgress ||
      old.cornerOpacity != cornerOpacity;
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/recommendation_card.dart
// ═══════════════════════════════════════════════════════

class RecommendationCard extends StatelessWidget {
  final Recommendation recommendation;

  const RecommendationCard({super.key, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final (borderColor, icon) = _style();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
          top: BorderSide(color: AppColors.border),
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommendation.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation.action,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (recommendation.details != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    recommendation.details!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _style() {
    switch (recommendation.priority) {
      case RecommendationPriority.critical:
        return (AppColors.nok, '🚨');
      case RecommendationPriority.high:
        return (AppColors.nok, '⚠️');
      case RecommendationPriority.medium:
        return (AppColors.warn, '🔧');
      case RecommendationPriority.low:
        return (AppColors.accent, '💡');
      case RecommendationPriority.preventive:
        return (AppColors.accent, '🛡️');
    }
  }
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/common/section_header.dart
// ═══════════════════════════════════════════════════════

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// lib/presentation/widgets/charts/grade_trend_chart.dart
// ═══════════════════════════════════════════════════════

class GradeTrendChart extends StatelessWidget {
  final List<double> grades;
  final double? ucl;
  final double? lcl;
  final double height;

  const GradeTrendChart({
    super.key,
    required this.grades,
    this.ucl,
    this.lcl,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Sin datos', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: grades.asMap().entries.map((entry) {
          final idx = entry.key;
          final grade = entry.value;
          final grade_ = ISOGrade.fromNumeric(grade);
          final color = AppColors.forGrade(grade_.letter);
          final barHeight = (grade / 4.0) * (height - 24);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedContainer(
                    duration: Duration(milliseconds: 300 + idx * 30),
                    height: barHeight.clamp(4, height - 24),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    grade_.letter,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrainsMono',
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
