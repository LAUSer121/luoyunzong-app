/// 派生统计：所有榜单、统计条、成绩统计都由此处纯函数计算，便于单测。
library;

import 'dart:math' as math;

import 'models.dart';

/// 通用统计项：标题 + 数值。
class StatChip {
  const StatChip(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

/// 职务构成统计。
List<StatChip> roleStats(Archive a) {
  int count(bool Function(Member) test) => a.memberList.where(test).length;
  return <StatChip>[
    StatChip('宗门总人数', '${a.memberList.length}'),
    StatChip(
      '弟子',
      '${count((Member m) => const <String>['外门弟子', '内门弟子', '核心弟子'].contains(m.role))}',
    ),
    StatChip(
      '天骄',
      '${count((Member m) => const <String>['天骄', '第二天骄', '第一天骄'].contains(m.role))}',
    ),
    StatChip('执事', '${count((Member m) => m.role == '执事')}'),
    StatChip('长老', '${count((Member m) => m.role == '长老')}'),
    StatChip('宗主', '${count((Member m) => m.role == '宗主')}'),
    StatChip('凡人', '${count((Member m) => m.role == '凡人')}'),
    StatChip('山峰', '${a.peakList.length}'),
  ];
}

/// 境界分布统计（六阶）。
List<StatChip> realmStats(Archive a) {
  return <StatChip>[
    for (final String rank in const <String>[
      '炼气',
      '筑基',
      '金丹',
      '元婴',
      '化神',
      '炼虚',
    ])
      StatChip(
        '$rank境',
        '${a.memberList.where((Member m) => m.mainRank == rank).length}',
      ),
  ];
}

/// 排行榜候选：剔除宗主与长老。
List<Member> rankingEligible(Archive a) =>
    a.memberList.where((Member m) => m.role != '宗主' && m.role != '长老').toList();

/// 姓名 + 数值的行。
class RankRow {
  const RankRow(this.name, this.display, {this.member, this.record});

  final String name;
  final String display;
  final Member? member;
  final TowerRecord? record;
}

/// 通天塔榜前三（用宗门名单当前职务判断是否剔除，离宗用快照职务）。
List<RankRow> towerTop(Archive a, {int limit = 3}) {
  final List<RankRow> rows = <RankRow>[];
  for (final TowerRecord t in a.towerList) {
    final Member? m = a.memberByName(t.name);
    final String role = m?.role ?? t.role;
    if (role == '宗主' || role == '长老') continue;
    rows.add(RankRow(t.name, '${t.passCount}', member: m, record: t));
  }
  rows.sort((RankRow x, RankRow y) {
    final int cx = int.tryParse(x.display) ?? 0;
    final int cy = int.tryParse(y.display) ?? 0;
    return cy.compareTo(cx);
  });
  return rows.take(limit).toList();
}

/// 修为榜前三。
List<RankRow> realmTop(Archive a, {int limit = 3}) {
  final List<Member> list = rankingEligible(a)
    ..sort((Member x, Member y) => y.realmScore.compareTo(x.realmScore));
  return list
      .take(limit)
      .map(
        (Member m) => RankRow(
          m.name,
          m.isMortal ? '凡体' : '${m.mainRank}境${m.subRank}',
          member: m,
        ),
      )
      .toList();
}

/// 贡献点榜前三。
List<RankRow> contributionTop(Archive a, {int limit = 3}) {
  final List<Member> list = rankingEligible(a)
    ..sort((Member x, Member y) => y.contribution.compareTo(x.contribution));
  return list
      .take(limit)
      .map((Member m) => RankRow(m.name, '${m.contribution}', member: m))
      .toList();
}

/// 山峰榜：总贡献最高的山峰。
Peak? peakTop(Archive a) {
  if (a.peakList.isEmpty) return null;
  final List<Peak> sorted = List<Peak>.of(a.peakList)
    ..sort((Peak x, Peak y) => y.total.compareTo(x.total));
  return sorted.first;
}

/// 兼任/荣誉徽章描述。
class SubRoleChip {
  const SubRoleChip(this.text, this.kind);

  final String text;

  /// `sub` 普通兼任 / `peak` 峰主 / `champ` 通天塔榜首。
  final String kind;
}

/// 计算某成员需要展示的兼任徽章（峰主·某峰、通天塔榜首等，去重）。
List<SubRoleChip> subRoleChips(Archive a, Member m) {
  final List<SubRoleChip> chips = <SubRoleChip>[];
  final bool champInSubs = m.subRoles.contains('通天塔榜首');
  for (final String r in m.subRoles) {
    if (r == '通天塔榜首') {
      chips.add(SubRoleChip('通天塔榜首', 'champ'));
    } else {
      chips.add(SubRoleChip(r, 'sub'));
    }
  }
  for (final Peak p in a.peakList) {
    if (p.leader == m.name) chips.add(SubRoleChip('峰主·${p.name}', 'peak'));
  }
  if (!champInSubs &&
      a.towerList.any((TowerRecord t) => t.isChampion && t.name == m.name)) {
    chips.add(SubRoleChip('通天塔榜首', 'champ'));
  }
  return chips;
}

/// 单场统计。
class ExamStats {
  const ExamStats({
    required this.count,
    required this.average,
    required this.max,
    required this.min,
    required this.excellentCount,
    required this.passCount,
    required this.failCount,
  });

  final int count;
  final double average;
  final double max;
  final double min;
  final int excellentCount;
  final int passCount;
  final int failCount;

  bool get isEmpty => count == 0;
}

ExamStats examStats(ExamSession? s, double threshold, double excellent) {
  if (s == null || s.records.isEmpty) {
    return const ExamStats(
      count: 0,
      average: 0,
      max: 0,
      min: 0,
      excellentCount: 0,
      passCount: 0,
      failCount: 0,
    );
  }
  final List<double> scores = s.records.map((ExamRecord r) => r.score).toList();
  final double sum = scores.fold<double>(0, (double a, double b) => a + b);
  final int ex = scores.where((double v) => v >= excellent).length;
  final int pass = scores
      .where((double v) => v >= threshold && v < excellent)
      .length;
  return ExamStats(
    count: scores.length,
    average: sum / scores.length,
    max: scores.reduce(math.max),
    min: scores.reduce(math.min),
    excellentCount: ex,
    passCount: pass,
    failCount: scores.length - ex - pass,
  );
}

/// 分数段。
class ScoreBand {
  const ScoreBand(this.label, this.count, this.percent);

  final String label;
  final int count;
  final int percent;
}

List<ScoreBand> examBands(ExamSession? s) {
  if (s == null || s.records.isEmpty) return const <ScoreBand>[];
  const List<List<Object>> defs = <List<Object>>[
    <Object>['90-100', 90.0, 1000.0],
    <Object>['80-89', 80.0, 89.999],
    <Object>['70-79', 70.0, 79.999],
    <Object>['60-69', 60.0, 69.999],
    <Object>['60以下', -1000.0, 59.999],
  ];
  final int n = s.records.length;
  return defs.map((List<Object> d) {
    final double min = d[1] as double;
    final double max = d[2] as double;
    final int c = s.records
        .where((ExamRecord r) => r.score >= min && r.score <= max)
        .length;
    return ScoreBand(d[0] as String, c, ((c / n) * 100).round());
  }).toList();
}

/// 三档名单。
class ExamZones {
  const ExamZones(this.excellent, this.pass, this.fail);

  final List<String> excellent;
  final List<String> pass;
  final List<String> fail;
}

ExamZones examZones(ExamSession? s, double threshold, double excellent) {
  if (s == null || s.records.isEmpty) {
    return const ExamZones(<String>[], <String>[], <String>[]);
  }
  return ExamZones(
    s.records
        .where((ExamRecord r) => r.score >= excellent)
        .map((ExamRecord r) => r.name)
        .toList(),
    s.records
        .where((ExamRecord r) => r.score >= threshold && r.score < excellent)
        .map((ExamRecord r) => r.name)
        .toList(),
    s.records
        .where((ExamRecord r) => r.score < threshold)
        .map((ExamRecord r) => r.name)
        .toList(),
  );
}

/// 山峰成绩汇总行。
class PeakExamRow {
  const PeakExamRow({
    required this.peak,
    this.count = 0,
    this.average,
    this.max,
  });

  final String peak;
  final int count;
  final double? average;
  final double? max;
}

/// 山峰汇总 + 全宗合计。
class PeakExamSummary {
  const PeakExamSummary({required this.rows, required this.total});

  final List<PeakExamRow> rows;
  final PeakExamRow total;
}

PeakExamSummary peakExamSummary(ExamSession? s, List<Peak> peaks) {
  final List<PeakExamRow> rows = <PeakExamRow>[];
  if (s == null || s.records.isEmpty) {
    return PeakExamSummary(
      rows: peaks.map((Peak p) => PeakExamRow(peak: p.name)).toList(),
      total: const PeakExamRow(peak: '全宗合计'),
    );
  }
  for (final Peak p in peaks) {
    final Set<String> names = p.members.map((PeakMember m) => m.name).toSet();
    final List<double> scores = s.records
        .where((ExamRecord r) => names.contains(r.name))
        .map((ExamRecord r) => r.score)
        .toList();
    if (scores.isEmpty) {
      rows.add(PeakExamRow(peak: p.name));
      continue;
    }
    final double sum = scores.fold<double>(0, (double a, double b) => a + b);
    rows.add(
      PeakExamRow(
        peak: p.name,
        count: scores.length,
        average: sum / scores.length,
        max: scores.reduce(math.max),
      ),
    );
  }
  rows.sort((PeakExamRow x, PeakExamRow y) {
    if (x.average == null && y.average == null) return 0;
    if (x.average == null) return 1;
    if (y.average == null) return -1;
    return y.average!.compareTo(x.average!);
  });
  final List<double> all = s.records.map((ExamRecord r) => r.score).toList();
  final double allSum = all.fold<double>(0, (double a, double b) => a + b);
  return PeakExamSummary(
    rows: rows,
    total: PeakExamRow(
      peak: '全宗合计',
      count: all.length,
      average: allSum / all.length,
      max: all.reduce(math.max),
    ),
  );
}

/// 两场对比行。
enum CompareStatus { normal, absent, added }

class CompareRow {
  const CompareRow({
    required this.name,
    required this.scoreA,
    required this.scoreB,
    required this.rankA,
    required this.rankB,
    required this.status,
  });

  final String name;
  final double? scoreA;
  final double? scoreB;
  final int? rankA;
  final int? rankB;
  final CompareStatus status;

  double? get diff =>
      (scoreA == null || scoreB == null) ? null : (scoreB! - scoreA!);

  /// 名次变化：正数表示进步（名次数字变小）。
  int? get rankChange =>
      (rankA == null || rankB == null) ? null : rankA! - rankB!;
}

/// 两场对比（以 B 场成绩降序，缺考/新增分别标注）。
List<CompareRow> compareSessions(ExamSession a, ExamSession b) {
  final List<String> names = <String>[];
  for (final ExamRecord r in <ExamRecord>[...a.records, ...b.records]) {
    if (!names.contains(r.name)) names.add(r.name);
  }
  final List<CompareRow> rows = names.map((String name) {
    final double? sa = a.scoreOf(name);
    final double? sb = b.scoreOf(name);
    final CompareStatus status = sb == null
        ? CompareStatus.absent
        : (sa == null ? CompareStatus.added : CompareStatus.normal);
    return CompareRow(
      name: name,
      scoreA: sa,
      scoreB: sb,
      rankA: a.rankOf(name),
      rankB: b.rankOf(name),
      status: status,
    );
  }).toList();
  rows.sort((CompareRow x, CompareRow y) {
    if (x.scoreB == null && y.scoreB == null) return 0;
    if (x.scoreB == null) return 1;
    if (y.scoreB == null) return -1;
    return y.scoreB!.compareTo(x.scoreB!);
  });
  return rows;
}

/// 个人历场追踪点。
class TrackPoint {
  const TrackPoint({
    required this.sessionName,
    required this.time,
    required this.score,
    required this.rank,
    required this.total,
  });

  final String sessionName;
  final String time;
  final double score;
  final int rank;
  final int total;
}

List<TrackPoint> trackData(ExamData data, String name) {
  final List<TrackPoint> points = <TrackPoint>[];
  for (final ExamSession s in data.sessions) {
    final double? score = s.scoreOf(name);
    if (score == null) continue;
    points.add(
      TrackPoint(
        sessionName: s.name,
        time: s.time,
        score: score,
        rank: s.rankOf(name) ?? 0,
        total: s.records.length,
      ),
    );
  }
  return points;
}
