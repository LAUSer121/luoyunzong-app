/// 宗门排行榜：通天塔 / 修为 / 贡献点 / 山峰，自动生成并剔除宗主与长老。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/analytics.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/badges.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/page_body.dart';
import '../../widgets/stat_chips.dart';

class RankingPage extends StatelessWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Archive archive = context.select<AppState, Archive>(
      (AppState s) => s.archive,
    );
    final List<RankRow> tower = towerTop(archive);
    final List<RankRow> realm = realmTop(archive);
    final List<RankRow> contrib = contributionTop(archive);
    final Peak? peak = peakTop(archive);

    return PageBody(
      children: <Widget>[
        const PageHeader(
          title: '宗门排行榜',
          subtitle: '数据随名单、通天塔与山峰的改动实时刷新；已剔除宗主与长老，山峰榜取总贡献第一的峰。',
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final bool wide = c.maxWidth >= 980;
            final List<Widget> cards = <Widget>[
              _rankCard('通天塔榜', '通关层数前三', tower, (RankRow r) => r.display),
              _rankCard('修为榜', '修为境界前三', realm, (RankRow r) => r.display),
              _rankCard('贡献点榜', '贡献点前三', contrib, (RankRow r) => r.display),
              _peakCard(peak),
            ];
            if (wide) {
              return Column(
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: cards[2]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: <Widget>[
                for (int i = 0; i < cards.length; i++) ...<Widget>[
                  cards[i],
                  if (i != cards.length - 1) const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _rankCard(
    String title,
    String subtitle,
    List<RankRow> rows,
    String Function(RankRow) valueOf,
  ) {
    return GlassCard(
      ornament: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(title, subtitle: subtitle),
          if (rows.isEmpty)
            const EmptyHint('暂无数据', icon: Icons.emoji_events_outlined)
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.4),
              },
              children: <TableRow>[
                for (int i = 0; i < rows.length; i++)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: <Widget>[
                            RankNumber(i),
                            const SizedBox(width: 10),
                            MedalName(rows[i].name, i),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          valueOf(rows[i]),
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (rows.length < 3)
                  for (int i = rows.length; i < 3; i++)
                    const TableRow(
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            '—',
                            style: TextStyle(color: AppColors.textFaint),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            '—',
                            style: TextStyle(color: AppColors.textFaint),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _peakCard(Peak? peak) {
    return GlassCard(
      ornament: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('山峰榜', subtitle: '总贡献第一的山峰'),
          if (peak == null)
            const EmptyHint('尚未创建山峰', icon: Icons.landscape_outlined)
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.4),
              },
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: <Widget>[
                          RankNumber(0),
                          const SizedBox(width: 10),
                          MedalName(peak.name, 0),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        peak.leader,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                TableRow(
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '总贡献',
                        style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${peak.total}',
                        style: const TextStyle(
                          color: AppColors.jade,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
