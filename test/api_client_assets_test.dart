/// 资源上传/下载链路：预签名直传优先，老接口回落。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luoyunzong/data/api_client.dart';

const String _token = 'test-token';

ApiClient _client(MockClient mock) =>
    ApiClient(baseUrl: 'https://api.example.com', token: _token, client: mock);

void main() {
  test('有预签名直传时：先签名 → 直传对象存储 → 登记到数据库', () async {
    final List<String> log = <String>[];
    final MockClient mock = MockClient((http.Request req) async {
      log.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/assets/sign') {
        expect(req.url.queryParameters['id'], 'abc123');
        expect(req.url.queryParameters['size'], '5');
        return http.Response(
          jsonEncode(<String, Object?>{
            'direct': true,
            'driver': 's3',
            'uploadUrl': 'https://s3.bitiful.net/my-media/luoyunzong/abc123.bin?X-Amz-Signature=x',
            'headers': <String, String>{
              'Content-Type': 'application/octet-stream',
              'x-amz-content-sha256': 'UNSIGNED-PAYLOAD',
            },
          }),
          200,
        );
      }
      if (req.method == 'PUT') {
        // 直传到对象存储：必须带上签过名的头，body 就是原始字节
        expect(req.headers['x-amz-content-sha256'], 'UNSIGNED-PAYLOAD');
        expect(req.bodyBytes.length, 5);
        return http.Response('', 200);
      }
      if (req.url.path == '/api/assets/commit') {
        return http.Response(jsonEncode(<String, Object?>{'ok': true}), 200);
      }
      return http.Response('{}', 404);
    });

    final String id = await _client(mock).uploadAsset(
      id: 'abc123',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      mime: 'application/octet-stream',
    );

    expect(id, 'abc123');
    expect(log, <String>[
      'POST /api/assets/sign',
      'PUT /my-media/luoyunzong/abc123.bin',
      'POST /api/assets/commit',
    ]);
  });

  test('服务端不支持直传（本地磁盘/老版本）：回落成 body 直传', () async {
    final List<String> log = <String>[];
    final MockClient mock = MockClient((http.Request req) async {
      log.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/assets/sign') {
        return http.Response(
          jsonEncode(<String, Object?>{'direct': false, 'driver': 'local'}),
          200,
        );
      }
      if (req.url.path == '/api/assets') {
        expect(req.bodyBytes.length, 3);
        return http.Response(jsonEncode(<String, Object?>{'id': 'x9'}), 200);
      }
      return http.Response('{}', 404);
    });

    final String id = await _client(mock).uploadAsset(
      id: 'x9',
      bytes: Uint8List.fromList(<int>[7, 8, 9]),
      mime: 'image/png',
    );

    expect(id, 'x9');
    expect(log, <String>['POST /api/assets/sign', 'POST /api/assets']);
  });

  test('老服务端没有签名接口（404）：同样回落', () async {
    final List<String> log = <String>[];
    final MockClient mock = MockClient((http.Request req) async {
      log.add('${req.method} ${req.url.path}');
      if (req.url.path == '/api/assets/sign') {
        return http.Response('not found', 404);
      }
      if (req.url.path == '/api/assets') {
        return http.Response(jsonEncode(<String, Object?>{'id': 'y1'}), 200);
      }
      return http.Response('{}', 404);
    });

    final String id = await _client(mock)
        .uploadAsset(id: 'y1', bytes: Uint8List.fromList(<int>[1]));

    expect(id, 'y1');
    expect(log, <String>['POST /api/assets/sign', 'POST /api/assets']);
  });

  test('取资源链接：相对路径补成绝对地址（本地驱动走本服务）', () async {
    final MockClient mock = MockClient((http.Request req) async {
      expect(req.url.path, '/api/assets/links');
      expect(req.url.queryParameters['ids'], 'a,b');
      return http.Response(
        jsonEncode(<String, Object?>{
          'a': '/assets/a.png',
          'b': 'https://s3.bitiful.net/my-media/luoyunzong/b.mp4?X-Amz-Signature=z',
        }),
        200,
      );
    });

    final Map<String, String> links = await _client(mock)
        .fetchAssetLinks(<String>['a', 'b']);

    expect(links['a'], 'https://api.example.com/assets/a.png');
    expect(links['b'], startsWith('https://s3.bitiful.net/'));
  });

  test('按链接下载字节；失败返回 null 不抛异常', () async {
    final MockClient mock = MockClient((http.Request req) async {
      if (req.url.path.endsWith('ok.bin')) {
        return http.Response.bytes(<int>[1, 2, 3], 200);
      }
      return http.Response('boom', 500);
    });

    final ApiClient client = _client(mock);
    expect(await client.downloadBytes('https://cdn.example.com/ok.bin'), <int>[
      1,
      2,
      3,
    ]);
    expect(
      await client.downloadBytes('https://cdn.example.com/bad.bin'),
      isNull,
    );
  });
}
