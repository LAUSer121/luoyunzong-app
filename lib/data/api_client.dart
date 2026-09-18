/// HTTP 客户端：面向后期接入的 MySQL 服务端（REST 约定见 docs/backend-mysql.md）。
library;

import 'dart:convert';

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

  /// 健康检查。
  Future<bool> ping() async {
    try {
      await _send(() => _client.get(_uri('/api/health'), headers: _headers));
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

  Future<void> putArchive(Archive archive) async {
    await _send(
      () => _client.put(
        _uri('/api/archive'),
        headers: _headers,
        body: jsonEncode(archive.toJson()),
      ),
    );
  }

  Future<void> deleteArchive() async {
    await _send(() => _client.delete(_uri('/api/archive'), headers: _headers));
  }

  void close() => _client.close();
}
