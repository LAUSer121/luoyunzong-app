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
      () => _client
          .get(_uri('/api/storage'), headers: _headers)
          .timeout(const Duration(seconds: 10)),
    );
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  /// 保存资源存储配置；[secretKey] 传空字符串表示「保持原来那把密钥」。
  Future<Map<String, Object?>> saveStorageConfig(
    Map<String, Object?> config,
  ) async {
    final Object? data = await _send(
      () => _client
          .put(
            _uri('/api/storage'),
            headers: _headers,
            body: jsonEncode(config),
          )
          .timeout(const Duration(seconds: 15)),
    );
    return data is Map ? data.cast<String, Object?>() : <String, Object?>{};
  }

  /// 让服务端实测一次「上传 → 回读」，返回 { ok, message }。
  ///
  /// 注意：测的是**服务端已保存的配置**，所以界面上要「先保存再测试」。
  Future<({bool ok, String message})> testStorage() async {
    try {
      final Object? data = await _send(
        () => _client
            .post(_uri('/api/storage/test'), headers: _headers)
            .timeout(const Duration(seconds: 60)),
      );
      final Map<String, Object?> map = data is Map
          ? data.cast<String, Object?>()
          : <String, Object?>{};
      return (
        ok: map['ok'] == true,
        message: '${map['message'] ?? (map['ok'] == true ? '测试通过' : '测试失败')}',
      );
    } catch (e) {
      return (ok: false, message: friendlyError(e));
    }
  }

  /// 读取服务端当前的上传上限（健康检查里就带着，无需额外鉴权）。
  /// 拿不到（离线/老服务端）返回 null，客户端就用内置默认值。
  Future<({int videoMaxMB, int videoMaxSeconds, int imageMaxMB})?>
  fetchUploadLimits() async {
    try {
      final Object? data = await _send(
        () => _client
            .get(_uri('/api/health'), headers: _headers)
            .timeout(const Duration(seconds: 4)),
      );
      if (data is! Map) return null;
      final Object? limits = data['limits'];
      if (limits is! Map) return null;
      int intOf(Object? v, int fallback) =>
          v is num && v > 0 ? v.toInt() : fallback;
      return (
        videoMaxMB: intOf(limits['videoMaxMB'], 20),
        videoMaxSeconds: limits['videoMaxSeconds'] is num
            ? (limits['videoMaxSeconds'] as num).toInt()
            : 25,
        imageMaxMB: intOf(limits['imageMaxMB'], 20),
      );
    } catch (_) {
      return null;
    }
  }

  /// 把网络异常翻译成「人话」，别把 SocketException 甩给用户。
  String friendlyError(Object e) {
    final String raw = '$e';
    final bool unreachable =
        raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('Connection refused') ||
        raw.contains('拒绝') ||
        raw.contains('Failed host lookup') ||
        raw.contains('TimeoutException') ||
        raw.contains('timed out');
    if (unreachable) {
      return '连不上服务端（$baseUrl）。\n'
          '先在电脑上把服务端跑起来：powershell -File server\\start-server.ps1\n'
          '（跑起来后再回到这里点「测试连接」）';
    }
    return '请求失败：$e';
  }

  Future<void> deleteArchive() async {
    await _send(() => _client.delete(_uri('/api/archive'), headers: _headers));
  }

  /// 清空云端资源索引（管理员「重置云端」时可选），返回删掉的条数。
  Future<int> deleteAllAssets() async {
    final Object? data = await _send(
      () => _client.delete(_uri('/api/assets'), headers: _headers),
    );
    if (data is Map && data['deleted'] is num) {
      return (data['deleted'] as num).toInt();
    }
    return 0;
  }

  // ------------------------------------------------------------------
  // 资源（头像 / 立绘 / 背景图 / 动态视频）
  // 存档里只存 `asset:<id>`，字节通过这两个接口收进 MySQL 的 assets 表
  // （或转存到对象存储后返回 URL）。
  // ------------------------------------------------------------------

  /// 上传一个资源；服务端按 id 去重。
  ///
  /// 优先走「预签名直传」：服务端只签名，字节由客户端**直接进对象存储**——
  /// 这样大视频不受 serverless 的 4.5MB 请求体上限影响，也不占服务端带宽。
  /// 服务端不支持直传时（本地磁盘 / 又拍云 / 老版本）自动回落到老接口。
  Future<String> uploadAsset({
    required String id,
    required List<int> bytes,
    String mime = 'application/octet-stream',
  }) async {
    final Map<String, Object?>? signed = await _signUpload(
      id: id,
      mime: mime,
      size: bytes.length,
    );
    if (signed != null) {
      final String uploadUrl = '${signed['uploadUrl'] ?? ''}';
      if (uploadUrl.isNotEmpty) {
        final Map<String, String> headers = <String, String>{};
        final Object? raw = signed['headers'];
        if (raw is Map) {
          for (final MapEntry<Object?, Object?> e in raw.entries) {
            headers['${e.key}'] = '${e.value}';
          }
        }
        final http.Response put = await _client
            .put(Uri.parse(uploadUrl), headers: headers, body: bytes)
            .timeout(const Duration(minutes: 5));
        if (put.statusCode < 200 || put.statusCode >= 300) {
          throw ApiException(
            put.statusCode,
            '直传对象存储失败：${utf8.decode(put.bodyBytes, allowMalformed: true)}',
          );
        }
        // 直传成功后登记到数据库（资源 id → 存储位置）
        await _send(
          () => _client.post(
            _uri('/api/assets/commit', <String, String>{
              'id': id,
              'mime': mime,
              'size': '${bytes.length}',
            }),
            headers: _headers,
          ),
        );
        return id;
      }
    }
    // 回落：老接口（body 直接传字节）
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

  /// 问服务端要一个上传用的预签名 URL；不支持直传时返回 null。
  Future<Map<String, Object?>?> _signUpload({
    required String id,
    required String mime,
    required int size,
  }) async {
    try {
      final Object? data = await _send(
        () => _client
            .post(
              _uri('/api/assets/sign', <String, String>{
                'id': id,
                'mime': mime,
                'size': '$size',
              }),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 20)),
      );
      if (data is Map && data['direct'] == true) {
        return data.cast<String, Object?>();
      }
    } catch (_) {
      // 404（老服务端）或网络问题 → 回落老接口
    }
    return null;
  }

  /// 批量拿到资源的**可下载地址**（对象存储给预签名 GET；本地磁盘给本服务直链）。
  ///
  /// 比 `fetchAssets` 更省：不把 base64 塞进一个大 JSON，大视频也不会超时。
  Future<Map<String, String>> fetchAssetLinks(Iterable<String> ids) async {
    final List<String> list = ids.toList();
    if (list.isEmpty) return <String, String>{};
    final Object? data = await _send(
      () => _client
          .get(
            _uri('/api/assets/links', <String, String>{'ids': list.join(',')}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30)),
    );
    final Map<String, String> out = <String, String>{};
    if (data is Map) {
      for (final MapEntry<Object?, Object?> e in data.entries) {
        final String u = '${e.value}';
        if (u.isEmpty) continue;
        // 相对路径（本地驱动）补成绝对地址
        out['${e.key}'] = u.startsWith('http') ? u : '$baseUrl$u';
      }
    }
    return out;
  }

  /// 按链接把字节下回来（给 [fetchAssetLinks] 用）。
  Future<Uint8List?> downloadBytes(String url) async {
    try {
      final http.Response res = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(minutes: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// 批量拉取资源（返回 id → 字节）；缺失的 id 不会出现在结果里。
  /// 老接口，保留作兜底。
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
