/// 统计条与空态。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/analytics.dart';

/// 统计项网格：自动换行的「数值 + 标签」卡片。
class StatChipWrap extends StatelessWidget {
  const StatChipWrap({
    required this.chips,
    this.valueColor,
    this.minWidth = 104,
    super.key,
  });

  final List<StatChip> chips;
  final Color? valueColor;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: chips
          .map(
            (StatChip c) => Container(
              constraints: BoxConstraints(minWidth: minWidth),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x33101A2E),
                border: Border.all(color: AppColors.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    c.value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.highlight
                          ? AppColors.jade
                          : (valueColor ?? AppColors.gold),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.label,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// 统一空态提示。
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {this.icon = Icons.inbox_outlined, super.key});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 34, color: AppColors.textFaint),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
