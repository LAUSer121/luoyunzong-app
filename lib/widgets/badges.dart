/// 徽章组件：职务、境界、兼任职衔、名次姓名。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../domain/analytics.dart';
import '../domain/models.dart';
import '../state/app_state.dart';

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {this.dense = false, super.key});

  final String role;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color c = roleColor(role);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        border: Border.all(color: c.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: TextStyle(
          color: c,
          fontSize: dense ? 11 : 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 境界徽章：凡人固定显示「凡体」。
class RealmBadge extends StatelessWidget {
  const RealmBadge({
    required this.mainRank,
    required this.subRank,
    this.dense = false,
    super.key,
  });

  factory RealmBadge.of(Member m, {bool dense = false}) =>
      RealmBadge(mainRank: m.mainRank, subRank: m.subRank, dense: dense);

  final String mainRank;
  final String subRank;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (mainRank == kMortalRealm || mainRank.isEmpty) {
      return _pill(kMortalRealm, AppColors.textFaint);
    }
    return _pill('$mainRank境$subRank', rankColor(mainRank));
  }

  Widget _pill(String text, Color color) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: dense ? 7 : 9,
      vertical: dense ? 2 : 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: dense ? 11 : 12),
    ),
  );
}

/// 兼任徽章组：普通兼任、峰主·某峰、通天塔榜首。
class SubRoleChips extends StatelessWidget {
  const SubRoleChips({required this.member, super.key});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final Archive archive = context.select<AppState, Archive>(
      (AppState s) => s.archive,
    );
    final List<SubRoleChip> chips = subRoleChips(archive, member);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips.map((SubRoleChip c) {
        final Color color = switch (c.kind) {
          'champ' => const Color(0xFFFFD766),
          'peak' => const Color(0xFFFFC98A),
          _ => AppColors.violet,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(c.text, style: TextStyle(color: color, fontSize: 11)),
        );
      }).toList(),
    );
  }
}

/// 名次姓名：前三名按金银铜着色。
class MedalName extends StatelessWidget {
  const MedalName(this.name, this.index, {this.bold = true, super.key});

  final String name;
  final int index;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      style: TextStyle(
        color: rankMedalColor(index),
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        fontSize: 14,
      ),
    );
  }
}

/// 位次：前三名高亮。
class RankNumber extends StatelessWidget {
  const RankNumber(this.index, {super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    final bool top = index < 3;
    return Container(
      width: 30,
      height: 26,
      alignment: Alignment.center,
      decoration: top
          ? BoxDecoration(
              color: rankMedalColor(index).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: rankMedalColor(index).withValues(alpha: 0.5),
              ),
            )
          : null,
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: top ? rankMedalColor(index) : AppColors.textMuted,
          fontWeight: top ? FontWeight.w700 : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }
}
