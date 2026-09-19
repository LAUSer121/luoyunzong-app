/// HTTP 客户端：面向后期接入的 MySQL 服务端（REST 约定见 docs/backend-mysql.md）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 极简 REST 客户端，所有方法都返回 JSON 可序列化对象。
class ApiClient {
  ApiClient({required String baseUrl, this.token, http.Client? client})
    : baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// 访问令牌（Bearer）。
  String? token;

  Map<String, String> get _headers => <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Object?> _send(Future<http.Response> Function() run) async {
    final http.Response res = await run();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.bodyBytes.isEmpty) return null;
      final String text = utf8.decode(res.bodyBytes);
      if (text.isEmpty) return null;
      return jsonDecode(text);
    }
    throw ApiException(res.statusCode, utf8.decode(res.bodyBytes));
  }

  /// 健康检查（限时，避免启动时被不可达地址拖住）。
  Future<bool> ping({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      await _send(() => _client.get(_uri('/api/health'), headers: _headers))
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 校验管理员密码（服务端校验，替代本地明文比对）。
  Future<bool> verifyPassword(String password) async {
    final Object? data = await _send(
      () => _client.post(
        _uri('/api/auth/verify'),
        headers: _headers,
        body: jsonEncode(<String, Object?>{'password': password}),
      ),
    );
    return data is Map && data['ok'] == true;
  }

  Future<Archive?> fetchArchive() async {
    final Object? data = await _send(
      () => _client.get(_uri('/api/archive'), headers: _headers),
    );
    if (data is Map) return Archive.fromJson(data.cast<String, Object?>());
    return null;
  }

  /// 读取存档并带回同步元信息（revision / 服务端更新时间）。
  ///
  /// 服务端没有存档时返回 `archive: null, revision: 0`（不算错误），
  /// 这样首次同步可以直接把本地存档推上去。
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  fetchArchiveMeta() async {
    final http.Response res = await _client
        .get(_uri('/api/archive'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) {
      return (archive: null, revision: 0, updatedAt: null);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    final int revision = int.tryParse(res.headers['x-revision'] ?? '') ?? 0;
    final DateTime? updatedAt = DateTime.tryParse(
      res.headers['x-updated-at'] ?? '',
    );
    final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final Archive? archive = decoded is Map
        ? Archive.fromJson(decoded.cast<String, Object?>())
        : null;
    return (archive: archive, revision: revision, updatedAt: updatedAt);
  }

  Future<void> putArchive(Archive archive) async {
    await _send(
      () => _client.put(
        _uri('/api/archive'),
        headers: _headers,
        body: jsonEncode(archive.toJson()),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 对象存储配置（管理员在设置页改；存在服务端 MySQL 里）
  // ---------------------------------------------------------------------------

  /// 读取服务端当前的资源存储配置（密钥只回「有没有设置」，不回明文）。
  Future<Map<String, Object?>> fetchStorageConfig() async {
    final Object? data = await _send(
      () => _client.get(_uri('/api/storage'), headers: _headers),
    );
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  /// 保存资源存储配置；[secretKey] 传空字符串表示「保持原来那把密钥」。
  Future<Map<String, Object?>> saveStorageConfig(
    Map<String, Object?> config,
  ) async {
    final Object? data = await _send(
      () => _client.put(
        _uri('/api/storage'),
        headers: _headers,
        body: jsonEncode(config),
      ),
    );
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  /// 让服务端实测一次「上传 → 回读」，返回 { ok, message }。
  Future<({bool ok, String message})> testStorage() async {
    try {
      final Object? data = await _send(
        () => _client.post(_uri('/api/storage/test'), headers: _headers),
      );
      final Map<String, Object?> map = data is Map
          ? data.cast<String, Object?>()
          : <String, Object?>{};
      return (
        ok: map['ok'] == true,
        message: '${map['message'] ?? (map['ok'] == true ? '测试通过' : '测试失败')}',
      );
    } catch (e) {
      return (ok: false, message: '请求失败：$e');
    }
  }

  Future<void> deleteArchive() async {
    await _send(() => _client.delete(_uri('/api/archive'), headers: _headers));
  }

  // ------------------------------------------------------------------
  // 资源（头像 / 立绘 / 背景图 / 动态视频）
  // 存档里只存 `asset:<id>`，字节通过这两个接口收进 MySQL 的 assets 表
  // （或转存到对象存储后返回 URL）。
  // ------------------------------------------------------------------

  /// 上传一个资源；服务端按 id 去重。
  Future<String> uploadAsset({
    required String id,
    required List<int> bytes,
    String mime = 'application/octet-stream',
  }) async {
    final Object? data = await _send(
      () => _client.post(
        _uri('/api/assets', <String, String>{'id': id, 'mime': mime}),
        headers: <String, String>{
          ..._headers,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      ),
    );
    if (data is Map && data['id'] is String) return data['id'] as String;
    return id;
  }

  /// 批量拉取资源（返回 id → 字节）；缺失的 id 不会出现在结果里。
  Future<Map<String, Uint8List>> fetchAssets(Iterable<String> ids) async {
    final List<String> list = ids.toList();
    if (list.isEmpty) return <String, Uint8List>{};
    final Object? data = await _send(
      () => _client.get(
        _uri('/api/assets/batch', <String, String>{'ids': list.join(',')}),
        headers: _headers,
      ),
    );
    final Map<String, Uint8List> out = <String, Uint8List>{};
    if (data is Map) {
      for (final MapEntry<Object?, Object?> e in data.entries) {
        final Object? value = e.value;
        if (value is String && value.isNotEmpty) {
          try {
            out['${e.key}'] = base64Decode(value);
          } catch (_) {
            // 跳过损坏的资源
          }
        }
      }
    }
    return out;
  }

  void close() => _client.close();
}
