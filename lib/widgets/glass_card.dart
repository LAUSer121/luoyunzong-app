/// 卡片与标题：统一的「玉牌」视觉（金色描边 + 四角云纹）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.ornament = false,
    this.texture = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool ornament;

  /// 底纹：极淡的云纹/菱格，让大块纯色面板不那么平。
  final bool texture;

  @override
  Widget build(BuildContext context) {
    // 背景色交给 Material：这样卡片内部的 ListTile / InkWell 水波纹才可见，
    // 也避免 Flutter 关于「DecoratedBox 遮挡 ListTile 背景」的断言。
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surfaceHigh.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppColors.goldDeep.withValues(alpha: 0.06),
                Colors.transparent,
                AppColors.info.withValues(alpha: 0.03),
              ],
            ),
            boxShadow: <BoxShadow>[
              // 内发光，做出「玉牌」的厚度感
              BoxShadow(
                color: AppColors.goldDeep.withValues(alpha: 0.07),
                blurRadius: 24,
                spreadRadius: -12,
                blurStyle: BlurStyle.inner,
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              if (texture)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _LatticePainter()),
                  ),
                ),
              if (ornament)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _CornerOrnamentPainter()),
                  ),
                ),
              // 顶部一道金线，像匾额的边
              const Positioned(
                left: 16,
                right: 16,
                top: 0,
                child: IgnorePointer(child: _TopSheen()),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部金色渐变细线。
class _TopSheen extends StatelessWidget {
  const _TopSheen();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            AppColors.gold.withValues(alpha: 0.55),
            AppColors.goldDeep.withValues(alpha: 0.35),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.25, 0.6, 1],
        ),
      ),
    );
  }
}

/// 极淡的菱格底纹（约 3% 透明度，几乎不抢内容）。
class _LatticePainter extends CustomPainter {
  const _LatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.gold.withValues(alpha: 0.035);
    const double step = 26;
    final Path path = Path();
    // 斜向菱格
    for (double x = -size.height; x < size.width; x += step) {
      path
        ..moveTo(x, 0)
        ..lineTo(x + size.height, size.height);
    }
    for (double x = 0.0; x < size.width + size.height; x += step) {
      path
        ..moveTo(x, 0)
        ..lineTo(x - size.height, size.height);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
          // 小菱形印 + 竖条，做出「宗门匾额」的感觉
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '◆',
              style: TextStyle(
                color: AppColors.goldDeep.withValues(alpha: 0.9),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[AppColors.gold, AppColors.goldDark],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: AppColors.gold, letterSpacing: 1.2),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                        height: 1.6,
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
