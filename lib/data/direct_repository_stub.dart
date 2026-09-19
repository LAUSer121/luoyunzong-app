/// Web 端（浏览器）的直连占位实现。
///
/// 浏览器开不了原始 TCP 连接，所以直连模式在 Web 上不可用 —— 这里保留同样的
/// 接口，让上层代码编译得过；实际运行时 `AppConfig.canDirect` 为 false，
/// 根本不会创建它（Web 版依旧用本地存档 / 服务端模式）。
library;

import 'dart:async';
import 'dart:typed_data';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'direct_types.dart';
import 's3_client.dart';

class DirectRepository implements LuoyunRepository {
  DirectRepository({required this.db, this.s3, this.fallback, Object? pool});

  final DbConfig db;
  final S3Config? s3;
  final LuoyunRepository? fallback;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  bool get isOffline => true;
  int get revision => 0;
  DateTime? get updatedAt => null;
  S3Client? get s3Client => null;

  @override
  String get label => '云端直连（Web 版不支持，已用本地存档）';

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> ensureS3() async {}

  Future<void> reconfigure(DbConfig next) async {}

  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  loadMeta() async => (archive: await load(), revision: 0, updatedAt: null);

  @override
  Future<Archive?> load() async => fallback?.load();

  @override
  Future<void> save(Archive archive) async => fallback?.save(archive);

  @override
  Future<void> clear() async => fallback?.clear();

  Future<int> deleteAllAssets() async => 0;

  Future<Archive?> snapshotArchive() async => null;

  Future<Uint8List?> readAsset({
    required String id,
    required String mime,
  }) async => null;

  Future<Map<String, Object?>?> readSetting(String key) async => null;

  Future<void> writeSetting(String key, Map<String, Object?> value) async {}

  void dispose() => _changes.close();
}
