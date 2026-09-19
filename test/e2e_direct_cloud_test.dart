/// 真机验证：App 直连 Aiven MySQL + 缤纷云（不需要任何服务器）。
///
/// 默认跳过，手动跑：
///   $env:LUOYUNZONG_E2E_DB='1'
///   $env:LUOYUNZONG_E2E_DB_PASSWORD='server/.env 里的 DB_PASSWORD'
///   $env:LUOYUNZONG_E2E_S3_KEY='缤纷云 SecretKey'
///   flutter test test/e2e_direct_cloud_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';

import 'package:luoyunzong/data/direct_repository.dart';
import 'package:luoyunzong/data/s3_client.dart';
import 'package:luoyunzong/domain/models.dart';

Archive _archive(String notice) {
  final Archive a = Archive()..notice = notice;
  a.memberList.add(Member(name: '测试弟子', role: '外门弟子'));
  return a;
}

void main() {
  // 真机联网：先起绑定（mysql_client 需要），再摘掉 flutter_test 的 HTTP 拦截
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final bool enabled = Platform.environment['LUOYUNZONG_E2E_DB'] == '1';
  final String dbPassword =
      Platform.environment['LUOYUNZONG_E2E_DB_PASSWORD'] ?? '';
  final String s3Key = Platform.environment['LUOYUNZONG_E2E_S3_KEY'] ?? '';

  const DbConfig db = DbConfig(
    host: 'mysql-3818918f-jsjsjsnxjns-6e11.g.aivencloud.com',
    port: 23483,
    user: 'avnadmin',
    password: '',
    database: 'defaultdb',
  );

  test('MySQL 直连：TLS 能连上并读到存档表', () async {
    final MySQLConnectionPool pool = MySQLConnectionPool(
      host: db.host,
      port: db.port,
      userName: db.user,
      password: dbPassword,
      databaseName: db.database,
      maxConnections: 2,
      secure: true,
      timeoutMs: 20000,
    );
    final IResultSet one = await pool.execute('SELECT 1 AS ok');
    expect('${one.rows.first.assoc()['ok']}', '1');
    final IResultSet rows = await pool.execute(
      'SELECT revision, CHAR_LENGTH(payload) AS len FROM archives WHERE org_id = :org LIMIT 1',
      <String, Object?>{'org': 'default'},
    );
    stdout.writeln(
      '[E2E-DB] 连接成功；archives 行数=${rows.rows.length}'
      '${rows.rows.isEmpty ? '' : ' revision=${rows.rows.first.assoc()['revision']} payload=${rows.rows.first.assoc()['len']}字节'}',
    );
    await pool.close();
  }, skip: enabled ? false : '需要真实数据库；设 LUOYUNZONG_E2E_DB=1 后运行');

  test('缤纷云直连：Dart 手写 SigV4 上传 / 下载 / 删除都通', () async {
    final S3Config cfg = S3Config(
      endpoint: 'https://s3.bitiful.net',
      region: 'cn-east-1',
      bucket: 'my-media',
      accessKey: Platform.environment['LUOYUNZONG_E2E_S3_AK'] ?? '',
      secretKey: s3Key,
    );
    expect(cfg.isComplete, isTrue, reason: '需要 AK/SK 环境变量');

    final S3Client s3 = S3Client(cfg);
    final String id = 'dart-probe-${DateTime.now().millisecondsSinceEpoch}';
    final Uint8List bytes = Uint8List.fromList(
      List<int>.generate(2048, (int i) => i % 251),
    );

    await s3.putObject(id: id, mime: 'application/octet-stream', bytes: bytes);
    stdout.writeln('[E2E-S3] 上传成功（Dart 签名有效）');

    final Uint8List? back = await s3.getObject(
      id: id,
      mime: 'application/octet-stream',
    );
    expect(back, isNotNull);
    expect(back!.length, bytes.length);

    // 预签名 PUT / GET（App 里大文件走的就是这条）
    final Uri putUrl = s3.presign(
      id: '$id-pre',
      mime: 'text/plain',
      method: 'PUT',
      expires: const Duration(minutes: 10),
    );
    final HttpClient client = HttpClient();
    final HttpClientRequest req = await client.putUrl(putUrl);
    req.headers.set('content-type', 'text/plain');
    req.headers.set('x-amz-content-sha256', 'UNSIGNED-PAYLOAD');
    req.add(<int>[104, 101, 108, 108, 111]);
    final HttpClientResponse res = await req.close();
    expect(res.statusCode, 200, reason: '预签名 PUT 应成功');
    stdout.writeln('[E2E-S3] 预签名 PUT 200');

    final Uri getUrl = s3.presign(
      id: '$id-pre',
      mime: 'text/plain',
      expires: const Duration(minutes: 10),
    );
    final HttpClientRequest getReq = await client.getUrl(getUrl);
    final HttpClientResponse getRes = await getReq.close();
    expect(getRes.statusCode, 200, reason: '预签名 GET 应成功');
    stdout.writeln('[E2E-S3] 预签名 GET 200');

    await s3.deleteObject(id: id, mime: 'application/octet-stream');
    await s3.deleteObject(id: '$id-pre', mime: 'text/plain');
    client.close();
    s3.close();
  }, skip: enabled ? false : '需要真实对象存储；设 LUOYUNZONG_E2E_DB=1 后运行');

  test('整体链路：DirectRepository 保存 → 读回（含资源直传）', () async {
    final DirectRepository repo = DirectRepository(
      db: DbConfig(
        host: db.host,
        port: db.port,
        user: db.user,
        password: dbPassword,
        database: db.database,
      ),
      s3: S3Config(
        endpoint: 'https://s3.bitiful.net',
        region: 'cn-east-1',
        bucket: 'my-media',
        accessKey: Platform.environment['LUOYUNZONG_E2E_S3_AK'] ?? '',
        secretKey: s3Key,
      ),
    );
    final Archive a = _archive('直连测试 ${DateTime.now().toIso8601String()}');
    final String big =
        'data:image/png;base64,'
        '${base64Encode(List<int>.generate(60000, (int i) => (i * 7) % 251))}';
    a.memberList.first.portrait = big;

    await repo.save(a);
    expect(repo.isOffline, isFalse, reason: '直连保存不应回落本地');
    stdout.writeln('[E2E-DIRECT] 保存成功（含 60KB 立绘直传）');

    final Archive? loaded = await repo.load();
    expect(loaded, isNotNull);
    expect(loaded!.notice, a.notice);
    expect(
      loaded.memberList.first.portrait?.isNotEmpty,
      isTrue,
      reason: '立绘应从对象存储读回',
    );
    stdout.writeln(
      '[E2E-DIRECT] 读回成功，立绘已还原（${loaded.memberList.first.portrait!.length} 字符）',
    );
    repo.dispose();
  }, skip: enabled ? false : '需要真实数据库 + 对象存储；设 LUOYUNZONG_E2E_DB=1 后运行');
}
