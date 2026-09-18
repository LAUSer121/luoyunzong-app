/// 个人成绩追踪折线图：实线为成绩（左轴）、虚线为排名（右轴）。
///
/// 用 CustomPainter 实现，避免图表库版本差异，绘制逻辑对齐旧版 canvas 版本。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/analytics.dart';

class ExamTrackChart extends StatelessWidget {
  const ExamTrackChart({required this.points, this.height = 230, super.key});

  final List<TrackPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x66101A2E),
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          '请选择成员查看其历场成绩与排名变化',
          style: TextStyle(color: AppColors.textFaint, fontSize: 13),
        ),
      );
    }
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0x66101A2E),
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: CustomPaint(painter: _TrackPainter(points), size: Size.infinite),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.points);

  final List<TrackPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const double padL = 40;
    const double padR = 46;
    const double padT = 26;
    const double padB = 30;
    final double cw = size.width - padL - padR;
    final double ch = size.height - padT - padB;
    if (cw <= 20 || ch <= 20) return;

    double maxS = 100;
    double minS = 0;
    for (final TrackPoint p in points) {
      if (p.score > maxS) maxS = p.score;
      if (p.score < minS) minS = p.score;
    }
    if (maxS <= minS) {
      maxS += 5;
      minS = math.max(0, minS - 5);
    }
    final int maxRank = math.max(
      2,
      points.map((TrackPoint p) => p.rank).reduce(math.max),
    );

    double xPos(int i) =>
        padL + (points.length == 1 ? cw / 2 : cw * i / (points.length - 1));
    double yScore(double v) => padT + ch - (v - minS) / (maxS - minS) * ch;
    double yRank(int v) => padT + (v - 1) / (maxRank - 1) * ch;

    // 网格与左轴刻度
    final Paint grid = Paint()
      ..color = const Color(0x47646E8C)
      ..strokeWidth = 1;
    final TextPainter scaleText = TextPainter(textDirection: TextDirection.ltr);
    for (int g = 0; g <= 4; g++) {
      final double gy = padT + ch * g / 4;
      canvas.drawLine(Offset(padL, gy), Offset(size.width - padR, gy), grid);
      final double value = maxS - (maxS - minS) * g / 4;
      scaleText
        ..text = TextSpan(
          text: value.round().toString(),
          style: const TextStyle(color: AppColors.textFaint, fontSize: 10),
        )
        ..layout();
      scaleText.paint(canvas, Offset(padL - scaleText.width - 5, gy - 6));
    }

    // 右轴排名刻度
    final TextPainter rankText = TextPainter(textDirection: TextDirection.ltr);
    for (int r = 1; r <= maxRank; r += math.max(1, (maxRank / 4).floor())) {
      final double gy = yRank(r);
      rankText
        ..text = TextSpan(
          text: '第$r',
          style: const TextStyle(color: Color(0xFF7DB8FF), fontSize: 10),
        )
        ..layout();
      rankText.paint(canvas, Offset(size.width - padR + 6, gy - 6));
    }

    // X 轴标签（场次名）
    final TextPainter label = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (int i = 0; i < points.length; i++) {
      final String name = points[i].sessionName;
      label
        ..text = TextSpan(
          text: name.length > 5 ? '${name.substring(0, 5)}…' : name,
          style: const TextStyle(color: AppColors.textFaint, fontSize: 10),
        )
        ..layout();
      label.paint(
        canvas,
        Offset(xPos(i) - label.width / 2, size.height - padB + 8),
      );
    }

    // 成绩实线
    final Paint scoreLine = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Path scorePath = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset o = Offset(xPos(i), yScore(points[i].score));
      if (i == 0) {
        scorePath.moveTo(o.dx, o.dy);
      } else {
        scorePath.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(scorePath, scoreLine);

    // 排名虚线
    final Paint rankLine = Paint()
      ..color = AppColors.info
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Path rankPath = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset o = Offset(xPos(i), yRank(points[i].rank));
      if (i == 0) {
        rankPath.moveTo(o.dx, o.dy);
      } else {
        rankPath.lineTo(o.dx, o.dy);
      }
    }
    _drawDashed(canvas, rankPath, rankLine);

    // 数据点与数值
    final TextPainter value = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < points.length; i++) {
      final Offset o = Offset(xPos(i), yScore(points[i].score));
      canvas.drawCircle(o, 3.5, Paint()..color = AppColors.gold);
      value
        ..text = TextSpan(
          text: points[i].score == points[i].score.roundToDouble()
              ? points[i].score.round().toString()
              : points[i].score.toString(),
          style: const TextStyle(color: AppColors.gold, fontSize: 10),
        )
        ..layout();
      value.paint(canvas, Offset(o.dx - value.width / 2, o.dy - 16));
      canvas.drawCircle(
        Offset(xPos(i), yRank(points[i].rank)),
        3.5,
        Paint()..color = AppColors.info,
      );
    }

    // 图例
    final TextPainter legend = TextPainter(textDirection: TextDirection.ltr);
    legend
      ..text = const TextSpan(
        text: '— 成绩',
        style: TextStyle(color: AppColors.gold, fontSize: 11),
      )
      ..layout();
    legend.paint(canvas, const Offset(padL, 4));
    legend
      ..text = const TextSpan(
        text: '- - 排名',
        style: TextStyle(color: AppColors.info, fontSize: 11),
      )
      ..layout();
    legend.paint(canvas, Offset(padL + 62, 4));
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    const double dash = 5;
    const double gap = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) =>
      oldDelegate.points != points;
}
