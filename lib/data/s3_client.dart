/// 缤纷云 S4 / 兼容 S3 的极简客户端（手写 SigV4，不引 SDK）。
///
/// 与服务端 `server/storage.mjs` 用同一套算法（那套已对缤纷云实测通过：
/// 直传 PUT 200、预签名 GET 200），这里移植到 Dart 客户端，让 App
/// **不经过任何服务器**直接读写对象存储。
///
/// - [putObject] / [getObject] / [deleteObject]：普通签名请求（服务端也能用）
/// - [presign]：查询串签名 URL（给别的设备/浏览器直连用）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 对象存储配置。
class S3Config {
  const S3Config({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.publicBase = '',
  });

  final String endpoint;
  final String region;
  final String bucket;
  final String accessKey;
  final String secretKey;

  /// 绑定的公开域名（留空则私有桶靠预签名/服务端中转）。
  final String publicBase;

  bool get isComplete =>
      endpoint.isNotEmpty &&
      bucket.isNotEmpty &&
      accessKey.isNotEmpty &&
      secretKey.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'endpoint': endpoint,
    'region': region,
    'bucket': bucket,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'publicBase': publicBase,
  };

  factory S3Config.fromJson(Map<String, Object?> json) => S3Config(
    endpoint: '${json['endpoint'] ?? ''}'.replaceAll(RegExp(r'/+$'), ''),
    region: '${json['region'] ?? 'cn-east-1'}',
    bucket: '${json['bucket'] ?? ''}',
    accessKey: '${json['accessKey'] ?? ''}',
    secretKey: '${json['secretKey'] ?? ''}',
    publicBase: '${json['publicBase'] ?? ''}'.replaceAll(RegExp(r'/+$'), ''),
  );
}

class S3Exception implements Exception {
  S3Exception(this.status, this.body);

  final int status;
  final String body;

  /// 把常见错误翻译成人话（和 App 里「测试连接」的提示保持一致）。
  String get hint {
    if (status == 403) {
      final bool denied = body.contains('AccessDenied');
      return denied
          ? '权限不足：去缤纷云控制台「子账户&Key」给这个子用户分配该桶的读写权限'
          : '签名不匹配：检查 AccessKey / SecretKey / Region 是否正确';
    }
    if (status == 404) return '桶名或 Endpoint 不对';
    if (status == 400) return '请求不合法（Region 或签名格式）';
    if (status == 413) return '文件太大';
    return '';
  }

  @override
  String toString() => '对象存储 HTTP $status $hint ${body.trim()}';
}

class S3Client {
  S3Client(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final S3Config config;
  final http.Client _client;

  static String _extOf(String mime) {
    const Map<String, String> map = <String, String>{
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
      'video/mp4': 'mp4',
      'video/webm': 'webm',
      'video/quicktime': 'mov',
    };
    return map[mime] ?? 'bin';
  }

  /// 资源在桶里的对象名（和 server/storage.mjs 完全一致，历史资源也能读到）。
  static String keyOf(String id, String mime) =>
      'luoyunzong/$id.${_extOf(mime)}';

  // ------------------------------------------------------------------
  // SigV4
  // ------------------------------------------------------------------

  static String _sha256Hex(List<int> data) => sha256.convert(data).toString();

  static List<int> _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static String _amzDate(DateTime t) =>
      '${t.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';

  /// 普通请求签名，返回可直接发的 headers。
  Map<String, String> _signHeaders({
    required String method,
    required String objectKey,
    required String payloadHash,
    String? contentType,
  }) {
    final DateTime now = DateTime.now().toUtc();
    final String amzDate = _amzDate(now);
    final String dateStamp = amzDate.substring(0, 8);
    final Uri url = Uri.parse('${config.endpoint}/${config.bucket}/$objectKey');

    final Map<String, String> headers = <String, String>{
      'host': url.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    if (contentType != null) headers['content-type'] = contentType;

    final List<String> keys = headers.keys.toList()..sort();
    final String canonicalHeaders = keys
        .map((String k) => '$k:${headers[k]}\n')
        .join();
    final String signedHeaders = keys.join(';');
    final String canonicalRequest =
        '$method\n/${config.bucket}/$objectKey\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

    final String scope = '$dateStamp/${config.region}/s3/aws4_request';
    final String stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_sha256Hex(utf8.encode(canonicalRequest))}';

    List<int> signingKey = _hmac(
      utf8.encode('AWS4${config.secretKey}'),
      dateStamp,
    );
    signingKey = _hmac(signingKey, config.region);
    signingKey = _hmac(signingKey, 's3');
    signingKey = _hmac(signingKey, 'aws4_request');
    final String signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    return <String, String>{
      ...headers,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=${config.accessKey}/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }

  Uri _objectUri(String objectKey) =>
      Uri.parse('${config.endpoint}/${config.bucket}/$objectKey');

  /// 上传对象（内存里一把传，视频也一样 —— 走的是直连，不过服务器）。
  Future<void> putObject({
    required String id,
    required String mime,
    required Uint8List bytes,
  }) async {
    final String key = keyOf(id, mime);
    final Map<String, String> headers = _signHeaders(
      method: 'PUT',
      objectKey: key,
      payloadHash: _sha256Hex(bytes),
      contentType: mime,
    );
    final http.Response res = await _client.put(
      _objectUri(key),
      headers: headers,
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw S3Exception(res.statusCode, res.body);
    }
  }

  /// 下载对象字节；不存在返回 null。
  Future<Uint8List?> getObject({
    required String id,
    required String mime,
  }) async {
    final String key = keyOf(id, mime);
    final Map<String, String> headers = _signHeaders(
      method: 'GET',
      objectKey: key,
      payloadHash: _sha256Hex(const <int>[]),
    );
    final http.Response res = await _client.get(
      _objectUri(key),
      headers: headers,
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw S3Exception(res.statusCode, res.body);
    }
    return res.bodyBytes;
  }

  /// 删除对象（失败不抛，清理用）。
  Future<void> deleteObject({required String id, required String mime}) async {
    final String key = keyOf(id, mime);
    try {
      final Map<String, String> headers = _signHeaders(
        method: 'DELETE',
        objectKey: key,
        payloadHash: _sha256Hex(const <int>[]),
      );
      await _client.delete(_objectUri(key), headers: headers);
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  /// 生成预签名 URL（[method] 为 `GET` 或 `PUT`）。
  ///
  /// 预签名一律用 `UNSIGNED-PAYLOAD`（缤纷云实测：PUT 用它可以；
  /// GET 也必须用它，否则会 403）。
  Uri presign({
    required String id,
    required String mime,
    String method = 'GET',
    Duration expires = const Duration(hours: 2),
  }) {
    final DateTime now = DateTime.now().toUtc();
    final String amzDate = _amzDate(now);
    final String dateStamp = amzDate.substring(0, 8);
    final String scope = '$dateStamp/${config.region}/s3/aws4_request';
    final String key = keyOf(id, mime);
    final Uri url = _objectUri(key);

    final Map<String, String> query = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '${config.accessKey}/$scope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '${expires.inSeconds.clamp(60, 604800)}',
      'X-Amz-SignedHeaders': 'host',
    };
    final List<String> sortedKeys = query.keys.toList()..sort();
    final String canonicalQuery = sortedKeys
        .map(
          (String k) =>
              '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(query[k]!)}',
        )
        .join('&');
    const String payloadHash = 'UNSIGNED-PAYLOAD';
    final String canonicalRequest =
        '$method\n/${config.bucket}/$key\n$canonicalQuery\nhost:${url.host}\n\nhost\n$payloadHash';
    final String stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_sha256Hex(utf8.encode(canonicalRequest))}';

    List<int> signingKey = _hmac(
      utf8.encode('AWS4${config.secretKey}'),
      dateStamp,
    );
    signingKey = _hmac(signingKey, config.region);
    signingKey = _hmac(signingKey, 's3');
    signingKey = _hmac(signingKey, 'aws4_request');
    final String signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    return Uri.parse(
      '${config.endpoint}/${config.bucket}/$key?$canonicalQuery&X-Amz-Signature=$signature',
    );
  }

  void close() => _client.close();
}
