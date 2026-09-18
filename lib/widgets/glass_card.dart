/// 卡片与标题：统一的「玉牌」视觉（金色描边 + 四角云纹）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.ornament = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool ornament;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          if (ornament)
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _CornerOrnamentPainter()),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// 分节标题：左侧金色竖条 + 标题文字 + 可选尾部操作。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.subtitle, this.trailing, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(width: 3, height: 18, color: AppColors.goldDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 页面标题：大号描金字 + 副标题。
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontSize: 26),
                ),
              ),
              ...?actions,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CornerOrnamentPainter extends CustomPainter {
  const _CornerOrnamentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint main = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = AppColors.goldDeep.withValues(alpha: 0.55);
    final Paint thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppColors.goldDeep.withValues(alpha: 0.28);
    const double s = 26;

    void corner(Offset origin, bool flipX, bool flipY) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
      final Path p = Path()
        ..moveTo(0, s)
        ..lineTo(0, 6)
        ..quadraticBezierTo(0, 0, 6, 0)
        ..lineTo(s, 0);
      canvas.drawPath(p, main);
      final Path p2 = Path()
        ..moveTo(0, s * 0.62)
        ..quadraticBezierTo(0, 8, 8, 8)
        ..lineTo(s * 0.62, 8);
      canvas.drawPath(p2, thin);
      canvas.restore();
    }

    corner(Offset.zero, false, false);
    corner(Offset(size.width, 0), true, false);
    corner(Offset(0, size.height), false, true);
    corner(Offset(size.width, size.height), true, true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
