/// 直连实现（桌面 / 手机）：不经过任何服务器，直接读写
///   · Aiven MySQL —— 存档（archives 表）、资源索引（assets 表）、运行配置（app_settings）
///   · 缤纷云 S4 —— 头像 / 立绘 / 背景 / 视频的字节（SigV4 手写签名，见 s3_client.dart）
///
/// 为什么要有这个：用户没有信用卡也没有实名，境外 PaaS 全要卡、国内云厂商必须实名，
/// 所以干脆把「服务端」搬进 App —— 数据本来就都在公网可达的云服务上。
///
/// 不支持的场景：**Web 版**（浏览器不能开原始 TCP），Web 上会回落本地存档。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mysql_client/mysql_client.dart';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'archive_codec.dart';
import 'direct_types.dart';
import 'asset_split.dart';
import 's3_client.dart';

/// 直连仓储：接口与 `ApiRepository` 一致，界面与同步逻辑完全不用改。
class DirectRepository implements LuoyunRepository {
  factory DirectRepository({
    required DbConfig db,
    S3Config? s3,
    LuoyunRepository? fallback,
    MySQLConnectionPool? pool,
  }) => DirectRepository._(db, s3, fallback, pool);

  DirectRepository._(this.db, this.s3, this.fallback, this._pool);

  final DbConfig db;
  S3Config? s3;
  final LuoyunRepository? fallback;
  MySQLConnectionPool? _pool;

  /// 对象存储配置是否已从数据库读过（只读一次，之后缓存）。
  bool _s3Loaded = false;

  /// 从数据库 `app_settings.storage` 里取对象存储配置（跟服务端读的是同一份）。
  ///
  /// 管理员在 App 的「云端资源存储」卡片里改过之后，两边都走这一份。
  Future<void> ensureS3() async {
    if (_s3Loaded) return;
    _s3Loaded = true;
    if (s3 != null && s3!.isComplete) return;
    try {
      final Map<String, Object?>? saved = await readSetting('storage');
      if (saved != null) {
        final S3Config cfg = S3Config.fromJson(saved);
        if (cfg.isComplete) s3 = cfg;
      }
    } catch (_) {
      // 读不到就只能内联存进存档（数据不丢，只是存档变大）
    }
  }

  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _offline = false;
  int _revision = 0;
  DateTime? _updatedAt;
  DbConfig? _dbInUse;

  /// 上一次读到的云端版本号 / 更新时间（同步判断「谁更新」用）。
  int get revision => _revision;
  DateTime? get updatedAt => _updatedAt;
  bool get isOffline => _offline;

  @override
  String get label => _offline ? '云端直连（离线，已回落本地）' : '云端直连';

  @override
  Stream<void> get changes => _changes.stream;

  S3Client? get s3Client =>
      (s3 != null && s3!.isComplete) ? S3Client(s3!) : null;

  Future<MySQLConnectionPool> _ensurePool() async {
    final DbConfig cfg = db;
    if (_pool != null && _dbInUse?.host == cfg.host) return _pool!;
    await _pool?.close();
    _pool = MySQLConnectionPool(
      host: cfg.host,
      port: cfg.port,
      userName: cfg.user,
      password: cfg.password,
      databaseName: cfg.database,
      maxConnections: 3,
      secure: true,
      timeoutMs: 15000,
    );
    _dbInUse = cfg;
    return _pool!;
  }

  /// 切换数据库连接参数（管理员在设置里改过之后调用）。
  Future<void> reconfigure(DbConfig next) async {
    if (next.host == _dbInUse?.host &&
        next.port == _dbInUse?.port &&
        next.user == _dbInUse?.user) {
      return;
    }
    await _pool?.close();
    _pool = null;
    _dbInUse = null;
  }

  // ------------------------------------------------------------------
  // 存档
  // ------------------------------------------------------------------

  @override
  Future<Archive?> load() async {
    try {
      await ensureS3();
      final MySQLConnectionPool pool = await _ensurePool();
      final IResultSet rows = await pool.execute(
        'SELECT payload, revision, updated_at FROM archives WHERE org_id = :org LIMIT 1',
        <String, Object?>{'org': db.orgId},
      );
      _offline = false;
      if (rows.rows.isEmpty) {
        _revision = 0;
        _updatedAt = null;
        return null;
      }
      final Map<String, Object?> row = _row(rows.rows.first);
      _revision = int.tryParse('${row['revision'] ?? 0}') ?? 0;
      _updatedAt = _parseDate(row['updated_at']);
      final Archive? archive = ArchiveCodec.decode('${row['payload'] ?? ''}');
      if (archive == null) return null;
      return await _restoreAssets(archive);
    } catch (_) {
      _offline = true;
      return await fallback?.load();
    }
  }

  /// 读取云端存档 + 版本信息（同步用）。
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  loadMeta() async {
    final Archive? loaded = await load();
    return (archive: loaded, revision: _revision, updatedAt: _updatedAt);
  }

  @override
  Future<void> save(Archive archive) async {
    try {
      await ensureS3();
      final MySQLConnectionPool pool = await _ensurePool();
      // 1) 大资源先直传对象存储，存档里只留 `asset:<id>` 引用
      final AssetSplit split = splitAssets(
        archive,
        // 没配对象存储时干脆不拆，全部内联进存档（至少数据不丢）
        thresholdBytes: s3Client == null ? 1 << 30 : 48 * 1024,
      );
      final S3Client? objects = s3Client;
      if (objects != null) {
        for (final AssetPayload asset in split.assets) {
          try {
            await objects.putObject(
              id: asset.id,
              mime: asset.mime,
              bytes: asset.bytes,
            );
            await pool.execute(
              'INSERT INTO assets (org_id, id, mime, byte_size, bytes, url, driver) '
              'VALUES (:org, :id, :mime, :size, NULL, NULL, :driver) '
              'ON DUPLICATE KEY UPDATE byte_size = VALUES(byte_size), driver = VALUES(driver)',
              <String, Object?>{
                'org': db.orgId,
                'id': asset.id,
                'mime': asset.mime,
                'size': asset.bytes.length,
                'driver': 's3',
              },
            );
          } catch (_) {
            // 单个资源失败不阻断整包保存（下次保存会重试）
          }
        }
      }
      // 2) 存档整体写回
      final String payload = ArchiveCodec.encodeJson(split.archive);
      await pool.execute(
        'INSERT INTO archives (org_id, payload, archive_version) '
        'VALUES (:org, :payload, :ver) '
        'ON DUPLICATE KEY UPDATE payload = VALUES(payload), revision = revision + 1',
        <String, Object?>{
          'org': db.orgId,
          'payload': payload,
          'ver': archive.archiveVersion,
        },
      );
      _offline = false;
    } catch (_) {
      _offline = true;
      await fallback?.save(archive);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> clear() async {
    try {
      final MySQLConnectionPool pool = await _ensurePool();
      await pool.execute(
        'DELETE FROM archives WHERE org_id = :org',
        <String, Object?>{'org': db.orgId},
      );
      _offline = false;
      _revision = 0;
      _updatedAt = null;
    } catch (_) {
      _offline = true;
    }
    await fallback?.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// 清空云端资源索引 + 对象存储里的对象（管理员「重置云端」用）。
  Future<int> deleteAllAssets() async {
    await ensureS3();
    final MySQLConnectionPool pool = await _ensurePool();
    final IResultSet rows = await pool.execute(
      'SELECT id, mime FROM assets WHERE org_id = :org',
      <String, Object?>{'org': db.orgId},
    );
    final S3Client? objects = s3Client;
    for (final ResultSetRow r in rows.rows) {
      final Map<String, Object?> row = _row(r);
      if (objects != null) {
        await objects.deleteObject(id: '${row['id']}', mime: '${row['mime']}');
      }
    }
    await pool.execute(
      'DELETE FROM assets WHERE org_id = :org',
      <String, Object?>{'org': db.orgId},
    );
    return rows.rows.length;
  }

  // ------------------------------------------------------------------
  // 资源
  // ------------------------------------------------------------------

  /// 读某个资源字节（同步逻辑/测试用）。
  Future<Uint8List?> readAsset({
    required String id,
    required String mime,
  }) async {
    final S3Client? objects = s3Client;
    if (objects == null) return null;
    return objects.getObject(id: id, mime: mime);
  }

  /// 把 `asset:<id>` 引用换成内嵌 data URL（直连对象存储取字节）。
  Future<Archive> _restoreAssets(Archive archive) async {
    final S3Client? objects = s3Client;
    if (objects == null) return archive;
    final Set<String> ids = referencedAssetIds(archive);
    if (ids.isEmpty) return archive;

    final MySQLConnectionPool pool = await _ensurePool();
    final Map<String, String> mimes = <String, String>{};
    try {
      // 资源表里记着每个资源的 mime —— 对象存储的对象名靠它拼（id.扩展名）
      // 注意：这个驱动只支持命名参数（:name），IN 里也要逐个命名。
      final List<String> idList = ids.toList();
      final Map<String, Object?> params = <String, Object?>{'org': db.orgId};
      final List<String> names = <String>[];
      for (int i = 0; i < idList.length; i++) {
        names.add(':id$i');
        params['id$i'] = idList[i];
      }
      final IResultSet rows = await pool.execute(
        'SELECT id, mime FROM assets WHERE org_id = :org AND id IN (${names.join(',')})',
        params,
      );
      for (final ResultSetRow r in rows.rows) {
        final Map<String, Object?> row = _row(r);
        mimes['${row['id']}'] = '${row['mime']}';
      }
    } catch (_) {
      // 查不到 mime 就按几种常见扩展名挨个试
    }

    final Map<String, Uint8List> assets = <String, Uint8List>{};
    for (final String id in ids) {
      final String? known = mimes[id];
      final List<String> tryMimes = known != null
          ? <String>[known]
          : <String>[
              'image/png',
              'image/jpeg',
              'image/webp',
              'video/mp4',
              'application/octet-stream',
            ];
      for (final String mime in tryMimes) {
        try {
          final Uint8List? bytes = await objects.getObject(id: id, mime: mime);
          if (bytes != null && bytes.isNotEmpty) {
            assets[id] = bytes;
            break;
          }
        } catch (_) {
          // 试下一个扩展名
        }
      }
    }
    return restoreAssets(archive, assets);
  }

  /// 管理员：读取运行配置（存储驱动的密钥等）。
  Future<Map<String, Object?>?> readSetting(String key) async {
    try {
      final MySQLConnectionPool pool = await _ensurePool();
      final IResultSet rows = await pool.execute(
        'SELECT svalue FROM app_settings WHERE org_id = :org AND skey = :k LIMIT 1',
        <String, Object?>{'org': db.orgId, 'k': key},
      );
      if (rows.rows.isEmpty) return null;
      final Map<String, Object?> row = _row(rows.rows.first);
      final Object? decoded = jsonDecode('${row['svalue'] ?? ''}');
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 管理员：写入运行配置。
  Future<void> writeSetting(String key, Map<String, Object?> value) async {
    final MySQLConnectionPool pool = await _ensurePool();
    await pool.execute(
      'INSERT INTO app_settings (org_id, skey, svalue) VALUES (:org, :k, :v) '
      'ON DUPLICATE KEY UPDATE svalue = VALUES(svalue)',
      <String, Object?>{'org': db.orgId, 'k': key, 'v': jsonEncode(value)},
    );
  }

  void dispose() {
    _changes.close();
    _pool?.close();
  }

  // ------------------------------------------------------------------
  // 结果解析小工具
  // ------------------------------------------------------------------

  static Map<String, Object?> _row(ResultSetRow row) {
    final Map<String, Object?> out = <String, Object?>{};
    row.assoc().forEach((String k, Object? v) => out[k] = v);
    return out;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse('$value')?.toUtc();
  }
}
