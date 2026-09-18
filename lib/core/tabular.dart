/// 表格文本解析：CSV / TSV / TXT → 二维网格，并自动猜测姓名列与成绩列。
library;

import '../domain/models.dart';

/// 解析分隔文本为二维网格（自动识别逗号 / 制表符 / 分号）。
List<List<String>> parseDelimited(String text) {
  final List<String> lines = text
      .split(RegExp(r'\r?\n'))
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return <List<String>>[];

  String separator = ',';
  if (lines.first.contains('\t')) {
    separator = '\t';
  } else if (lines.first.contains(';') && !lines.first.contains(',')) {
    separator = ';';
  }
  return lines
      .map(
        (String line) => line
            .split(separator)
            .map((String c) => c.trim().replaceAll('"', ''))
            .toList(),
      )
      .toList();
}

/// 猜测姓名列与成绩列（依据表头关键字，找不到时退回前两列）。
({int nameCol, int scoreCol}) guessColumns(List<List<String>> grid) {
  if (grid.isEmpty) return (nameCol: 0, scoreCol: 1);
  final List<String> header = grid.first;
  int nameCol = -1;
  int scoreCol = -1;
  for (int i = 0; i < header.length; i++) {
    final String h = header[i];
    if (nameCol == -1 &&
        RegExp(r'姓名|名字|name', caseSensitive: false).hasMatch(h)) {
      nameCol = i;
    }
    if (scoreCol == -1 &&
        RegExp(r'成绩|分数|得分|score', caseSensitive: false).hasMatch(h)) {
      scoreCol = i;
    }
  }
  if (nameCol == -1) nameCol = 0;
  if (scoreCol == -1) {
    scoreCol = nameCol == 0 ? (grid.first.length > 1 ? 1 : 0) : 0;
  }
  return (nameCol: nameCol, scoreCol: scoreCol);
}

/// 按列映射把网格转成成绩记录；表头行与空行自动跳过。
List<ExamRecord> gridToRecords(
  List<List<String>> grid, {
  required int nameCol,
  required int scoreCol,
  bool skipFirstRow = true,
}) {
  final List<ExamRecord> out = <ExamRecord>[];
  for (int r = skipFirstRow ? 1 : 0; r < grid.length; r++) {
    final List<String> row = grid[r];
    if (row.length <= nameCol) continue;
    final String name = row[nameCol].trim();
    if (name.isEmpty) continue;
    if (scoreCol >= row.length) continue;
    final double? score = double.tryParse(row[scoreCol].trim());
    if (score == null) continue;
    out.add(ExamRecord(name: name, score: score));
  }
  return out;
}

/// 表头是否像成绩表（含「姓名/成绩」等关键字）。
bool looksLikeHeader(List<String> row) {
  final String joined = row.join();
  return RegExp(r'姓名|名字|成绩|分数|得分|科目').hasMatch(joined) &&
      row.every((String c) => double.tryParse(c.trim()) == null);
}
