/// 纯逻辑解析工具：名单/成绩文本解析、时间与标签格式化。
library;

import '../domain/models.dart';
import 'constants.dart';

/// 分隔符：空格 / 中文顿号 / 中英文逗号 / 冒号 / 分号 / 竖线 / 制表符。
final RegExp _separator = RegExp(r'[\s,，、:：;；|\t]+');

/// 表头行（成绩导入时跳过）。
final RegExp _scoreHeader = RegExp(r'^(姓名|名字|成绩|分数|得分|科目)');

/// 「姓名 成绩」行。
final RegExp _scoreLine = RegExp(r'^(.+?)[\s,，、:：;；|\t]+(-?\d+(?:\.\d+)?)$');

/// 拆分一行为若干片段。
List<String> splitFields(String line) =>
    line.split(_separator).where((String s) => s.isNotEmpty).toList();

/// 成绩解析结果。
class ScoreParseResult {
  ScoreParseResult(this.valid, this.invalid);

  final List<ExamRecord> valid;
  final List<String> invalid;
}

/// 解析多行「姓名 成绩」文本，跳过表头与空行。
ScoreParseResult parseScoreLines(String text) {
  final List<ExamRecord> ok = <ExamRecord>[];
  final List<String> bad = <String>[];
  for (final String raw in text.split(RegExp(r'\r?\n'))) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (_scoreHeader.hasMatch(line)) continue;
    final RegExpMatch? m = _scoreLine.firstMatch(line);
    if (m == null) {
      bad.add(line.length > 30 ? '${line.substring(0, 30)}…' : line);
      continue;
    }
    final String name = m.group(1)!.trim();
    final double? score = double.tryParse(m.group(2)!);
    if (name.isEmpty || score == null) {
      bad.add(line.length > 30 ? '${line.substring(0, 30)}…' : line);
      continue;
    }
    ok.add(ExamRecord(name: name, score: score));
  }
  return ScoreParseResult(ok, bad);
}

/// 名单批量导入结果。
class MemberParseResult {
  MemberParseResult({
    required this.added,
    required this.duplicated,
    required this.invalidLines,
  });

  final List<Member> added;
  final List<String> duplicated;
  final List<String> invalidLines;
}

/// 解析名单文本：每行「姓名 职务 境界」，职务/境界缺省为外门弟子/炼气前期。
///
/// [existingNames] 中已存在的姓名会被跳过（同名不覆盖）。
MemberParseResult parseMemberLines(String text, Set<String> existingNames) {
  final List<Member> added = <Member>[];
  final List<String> duplicated = <String>[];
  final List<String> invalid = <String>[];
  final Set<String> seen = Set<String>.of(existingNames);

  for (final String raw in text.split(RegExp(r'\r?\n'))) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    final List<String> parts = splitFields(line);
    if (parts.isEmpty) {
      invalid.add(line);
      continue;
    }
    final String name = parts.first;
    final List<String> rest = parts.sublist(1).toList();

    String? role;
    for (int i = 0; i < rest.length; i++) {
      if (kRoleOptions.contains(rest[i])) {
        role = rest[i];
        rest.removeAt(i);
        break;
      }
    }
    final String joined = rest.join();
    String? main;
    for (final String candidate in kMainRankOptions) {
      if (joined.contains(candidate)) {
        main = candidate;
        break;
      }
    }
    String? sub;
    for (final String candidate in kSubRankOptions) {
      if (joined.contains(candidate)) {
        sub = candidate;
        break;
      }
    }

    if (seen.contains(name)) {
      duplicated.add(name);
      continue;
    }
    role ??= '外门弟子';
    main ??= '炼气';
    sub ??= '前期';
    if (role == '凡人') {
      main = '凡体';
      sub = '';
    }
    added.add(
      Member(
        name: name,
        role: role,
        mainRank: main,
        subRank: sub,
        subRoles: <String>[],
      ),
    );
    seen.add(name);
  }
  return MemberParseResult(
    added: added,
    duplicated: duplicated,
    invalidLines: invalid,
  );
}

/// 当前时间字符串：`2026-03-15 10:00`。
String nowTimeStr([DateTime? now]) {
  final DateTime t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 场次标签：`三月演武 03-15 10:00（28人）`。
String sessionLabel(ExamSession s, int index) {
  final int n = s.records.length;
  final String t = s.time.length >= 16 ? ' ${s.time.substring(5, 16)}' : '';
  final String name = s.name.isEmpty ? '场次${index + 1}' : s.name;
  return '$name$t（$n人）';
}

/// 数字展示：去掉多余小数位（`92.0` → `92`，`87.5` → `87.5`）。
String formatNumber(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return ((v * 100).round() / 100).toString();
}
