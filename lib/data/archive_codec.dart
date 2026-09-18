/// 存档文本编解码：与旧版 `落云宗存档.js` / `.json` 完全互通。
library;

import 'dart:convert';

import '../domain/models.dart';

/// 旧版导出文件里的全局变量名。
const String kLegacySaveSymbol = '__LUOYUN_SAVE__';

class ArchiveCodec {
  const ArchiveCodec._();

  /// 解析存档文本：支持纯 JSON、旧版 JS 存档、以及带 BOM 的文本。
  ///
  /// 失败返回 `null`（不抛异常，界面据此提示格式错误）。
  static Archive? decode(String text) {
    final Map<String, Object?>? json = decodeToMap(text);
    if (json == null) return null;
    try {
      return Archive.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 只做「文本 → Map」的解析，供导入前校验。
  static Map<String, Object?>? decodeToMap(String text) {
    String body = text.replaceFirst('\uFEFF', '').trim();
    if (body.isEmpty) return null;

    final int flag = body.indexOf(kLegacySaveSymbol);
    if (flag != -1) {
      final int eq = body.indexOf('=', flag);
      if (eq == -1) return null;
      body = body.substring(eq + 1).trim();
      if (body.endsWith(';')) body = body.substring(0, body.length - 1).trim();
    }

    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 导出为旧版可直接读取的 JS 存档（同目录自动加载）。
  static String encodeJs(Archive archive) {
    final String buffer = const JsonEncoder.withIndent('  ')
        .convert(archive.toJson());
    return '/* 落云宗自动存档：新版导出的文件，旧版网页放在同目录也可直接读取 */\n'
        'window.$kLegacySaveSymbol = $buffer;\n';
  }

  /// 导出为纯 JSON 存档。
  static String encodeJson(Archive archive, {bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(archive.toJson());
    }
    return jsonEncode(archive.toJson());
  }
}
