/// 轻量 XLSX 解析（离线可用）：直接读取 zip 中的 sheet1 与 sharedStrings。
///
/// 只处理文本/数值单元格，忽略样式与公式结果以外的复杂特性，足够成绩表场景。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 读取第一张工作表的二维网格（行 × 列，单元格为字符串）。
List<List<String>> readXlsxGrid(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  String sharedXml = '';
  String? sheetXml;

  for (final ArchiveFile file in archive.files) {
    if (!file.isFile) continue;
    final String name = file.name;
    if (name == 'xl/sharedStrings.xml') {
      sharedXml = _decode(file);
    } else if (sheetXml == null && name.startsWith('xl/worksheets/sheet')) {
      sheetXml = _decode(file);
    }
  }
  if (sheetXml == null) return <List<String>>[];
  return _parseSheet(sheetXml, _parseSharedStrings(sharedXml));
}

String _decode(ArchiveFile file) {
  final List<int> raw = file.content;
  try {
    return utf8.decode(raw);
  } catch (_) {
    return latin1.decode(raw);
  }
}

List<String> _parseSharedStrings(String? xml) {
  if (xml == null) return <String>[];
  final List<String> out = <String>[];
  for (final RegExpMatch si in RegExp(
    r'<si>(.*?)</si>',
    dotAll: true,
  ).allMatches(xml)) {
    final String inner = si.group(1) ?? '';
    final StringBuffer buffer = StringBuffer();
    for (final RegExpMatch t in RegExp(
      r'<t[^>]*>(.*?)</t>',
      dotAll: true,
    ).allMatches(inner)) {
      buffer.write(_unescape(t.group(1) ?? ''));
    }
    out.add(buffer.toString());
  }
  return out;
}

List<List<String>> _parseSheet(String xml, List<String> shared) {
  final List<List<String>> grid = <List<String>>[];
  for (final RegExpMatch row in RegExp(
    r'<row[^>]*>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final String rowXml = row.group(1) ?? '';
    final Map<int, String> cells = <int, String>{};
    int maxCol = -1;
    for (final RegExpMatch cell in RegExp(
      r'<c\s+r="([A-Z]+)\d+"([^>]*)>(.*?)</c>',
      dotAll: true,
    ).allMatches(rowXml)) {
      final int col = _columnIndex(cell.group(1) ?? 'A');
      final String attrs = cell.group(2) ?? '';
      final String body = cell.group(3) ?? '';
      final String? type = RegExp(r't="([^"]+)"').firstMatch(attrs)?.group(1);
      final String? rawValue = RegExp(
        r'<v>(.*?)</v>',
        dotAll: true,
      ).firstMatch(body)?.group(1);
      String value = '';
      if (rawValue != null) {
        value = _unescape(rawValue);
        if (type == 's') {
          final int idx = int.tryParse(value) ?? -1;
          value = (idx >= 0 && idx < shared.length) ? shared[idx] : '';
        }
      } else {
        final String? inline = RegExp(
          r'<is>.*?<t[^>]*>(.*?)</t>',
          dotAll: true,
        ).firstMatch(body)?.group(1);
        if (inline != null) value = _unescape(inline);
      }
      cells[col] = value;
      if (col > maxCol) maxCol = col;
    }
    if (maxCol < 0) continue;
    grid.add(List<String>.generate(maxCol + 1, (int i) => cells[i] ?? ''));
  }
  return grid;
}

int _columnIndex(String letters) {
  int value = 0;
  for (final int code in letters.codeUnits) {
    value = value * 26 + (code - 64);
  }
  return value - 1;
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
