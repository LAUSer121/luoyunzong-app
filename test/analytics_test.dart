import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/domain/analytics.dart';
import 'package:luoyunzong/domain/models.dart';

Archive _archive() {
  return Archive(
    memberList: <Member>[
      Member(
        name: '云逍遥',
        role: '宗主',
        mainRank: '炼虚',
        subRank: '大圆满',
        contribution: 999,
      ),
      Member(
        name: '林晚晴',
        role: '长老',
        mainRank: '化神',
        subRank: '后期',
        contribution: 500,
      ),
      Member(
        name: '沈青霜',
        role: '第一天骄',
        mainRank: '元婴',
        subRank: '中期',
        contribution: 300,
      ),
      Member(
        name: '苏白衣',
        role: '核心弟子',
        mainRank: '金丹',
        subRank: '大圆满',
        contribution: 200,
      ),
      Member(
        name: '陆离',
        role: '外门弟子',
        mainRank: '筑基',
        subRank: '前期',
        contribution: 10,
      ),
      Member(name: '小乞儿', role: '凡人', mainRank: '凡体'),
    ],
    towerList: <TowerRecord>[
      TowerRecord(name: '沈青霜', passCount: 62, isChampion: true),
      TowerRecord(name: '陆离', passCount: 12),
      TowerRecord(name: '云逍遥', passCount: 99),
      TowerRecord(name: '林晚晴', passCount: 88),
    ],
    peakList: <Peak>[
      Peak(
        name: '落云峰',
        leader: '沈青霜',
        members: <PeakMember>[
          PeakMember(name: '沈青霜', contribution: 120),
          PeakMember(name: '陆离', contribution: 30),
        ],
      ),
    ],
  );
}

void main() {
  test('统计条包含总人数与山峰数', () {
    final List<StatChip> chips = roleStats(_archive());
    expect(chips.first.value, '6');
    expect(chips.last.value, '1');
  });

  test('排行榜剔除宗主与长老', () {
    final Archive a = _archive();
    final List<RankRow> realm = realmTop(a);
    expect(realm.map((RankRow r) => r.name), <String>['沈青霜', '苏白衣', '陆离']);
    final List<RankRow> contrib = contributionTop(a);
    expect(contrib.first.name, '沈青霜');
    final List<RankRow> tower = towerTop(a);
    expect(tower.map((RankRow r) => r.name), <String>['沈青霜', '陆离']);
    expect(tower.first.display, '62');
  });

  test('山峰榜取总贡献最高', () {
    final Peak? top = peakTop(_archive());
    expect(top?.name, '落云峰');
    expect(top?.total, 150);
  });

  test('兼任徽章包含峰主与通天塔榜首', () {
    final Archive a = _archive();
    final Member m = a.memberByName('沈青霜')!;
    m.subRoles.add('通天塔榜首');
    final List<SubRoleChip> chips = subRoleChips(a, m);
    expect(chips.any((SubRoleChip c) => c.kind == 'peak'), isTrue);
    expect(chips.where((SubRoleChip c) => c.kind == 'champ').length, 1);
  });

  test('成绩统计、分数段与三档名单', () {
    final ExamSession s = ExamSession(
      id: 's1',
      name: '测试',
      records: <ExamRecord>[
        ExamRecord(name: '甲', score: 95),
        ExamRecord(name: '乙', score: 82),
        ExamRecord(name: '丙', score: 61),
        ExamRecord(name: '丁', score: 30),
      ],
    );
    final ExamStats stats = examStats(s, 60, 85);
    expect(stats.count, 4);
    expect(stats.excellentCount, 1);
    expect(stats.passCount, 2);
    expect(stats.failCount, 1);
    expect(stats.max, 95);
    expect(stats.min, 30);

    final List<ScoreBand> bands = examBands(s);
    expect(bands.first.count, 1);
    expect(bands.last.count, 1);

    final ExamZones zones = examZones(s, 60, 85);
    expect(zones.excellent, <String>['甲']);
    expect(zones.pass, <String>['乙', '丙']);
    expect(zones.fail, <String>['丁']);
  });

  test('两场对比给出差值与名次变化', () {
    final ExamSession a = ExamSession(
      id: 'a',
      name: 'A',
      records: <ExamRecord>[
        ExamRecord(name: '甲', score: 80),
        ExamRecord(name: '乙', score: 90),
      ],
    );
    final ExamSession b = ExamSession(
      id: 'b',
      name: 'B',
      records: <ExamRecord>[
        ExamRecord(name: '甲', score: 95),
        ExamRecord(name: '丙', score: 70),
      ],
    );
    final List<CompareRow> rows = compareSessions(a, b);
    final CompareRow jia = rows.firstWhere((CompareRow r) => r.name == '甲');
    expect(jia.scoreA, 80);
    expect(jia.scoreB, 95);
    expect(jia.diff, 15);
    expect(jia.rankChange, 1);
    final CompareRow bing = rows.firstWhere((CompareRow r) => r.name == '丙');
    expect(bing.status, CompareStatus.added);
    final CompareRow yi = rows.firstWhere((CompareRow r) => r.name == '乙');
    expect(yi.status, CompareStatus.absent);
  });

  test('个人追踪按场次顺序返回成绩与名次', () {
    final ExamData data = ExamData(
      sessions: <ExamSession>[
        ExamSession(
          id: 's1',
          name: '第一场',
          records: <ExamRecord>[ExamRecord(name: '甲', score: 70)],
        ),
        ExamSession(
          id: 's2',
          name: '第二场',
          records: <ExamRecord>[
            ExamRecord(name: '乙', score: 90),
            ExamRecord(name: '甲', score: 80),
          ],
        ),
      ],
    );
    final List<TrackPoint> points = trackData(data, '甲');
    expect(points.length, 2);
    expect(points.first.rank, 1);
    expect(points.last.score, 80);
    expect(points.last.rank, 2);
    expect(points.last.total, 2);
  });

  test('山峰汇总与全宗合计', () {
    final Archive a = _archive();
    final ExamSession s = ExamSession(
      id: 's',
      name: '演武',
      records: <ExamRecord>[
        ExamRecord(name: '沈青霜', score: 90),
        ExamRecord(name: '陆离', score: 60),
      ],
    );
    final PeakExamSummary summary = peakExamSummary(s, a.peakList);
    expect(summary.rows.single.peak, '落云峰');
    expect(summary.rows.single.count, 2);
    expect(summary.rows.single.average, 75);
    expect(summary.total.average, 75);
  });
}
