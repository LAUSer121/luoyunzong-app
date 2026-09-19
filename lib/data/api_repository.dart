/// 远端仓储：通过 HTTP + MySQL 服务端读写存档。
///
/// 与 `LocalRepository` 实现同一接口，切换数据源时只需在 `main.dart`
/// 里改一行构造，界面与业务逻辑完全不动。
library;

import 'dart:async';
import 'dart:typed_data';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'api_client.dart';
import 'asset_split.dart';

class ApiRepository implements LuoyunRepository {
  ApiRepository({required this.client, this.fallback});

  final ApiClient client;

  /// 网络不可用时的本地兜底仓储（可选）。
  final LuoyunRepository? fallback;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _offline = false;

  @override
  String get label => _offline ? '云端同步（离线，已回落本地）' : '云端同步';

  bool get isOffline => _offline;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Archive?> load() async {
    try {
      final ({Archive? archive, int revision, DateTime? updatedAt}) meta =
          await loadMeta();
      _offline = false;
      return meta.archive;
    } on Object {
      _offline = true;
      return fallback?.load();
    }
  }

  /// 读取云端存档并附带版本信息（云同步用：判断云端是否比我这边新）。
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  loadMeta() async {
    final ({Archive? archive, int revision, DateTime? updatedAt}) meta =
        await client.fetchArchiveMeta();
    final Archive? remote = meta.archive;
    if (remote == null) return meta;
    return (
      archive: await restoreAssetsOf(remote),
      revision: meta.revision,
      updatedAt: meta.updatedAt,
    );
  }

  /// 把存档里的大资源（`asset:<id>` 引用）还原成内嵌 data URL。
  ///
  /// 优先「批量取链接 + 直接下载」：对象存储回的是预签名地址，字节从缤纷云直接下来，
  /// 不经过服务端（serverless 上大视频走老接口会超时/超限）；失败再回落老的 base64 接口。
  Future<Archive> restoreAssetsOf(Archive remote) async {
    final Set<String> ids = referencedAssetIds(remote);
    if (ids.isEmpty) return remote;
    Map<String, Uint8List> assets = <String, Uint8List>{};
    try {
      final Map<String, String> links = await client.fetchAssetLinks(ids);
      final List<MapEntry<String, String>> entries = links.entries.toList();
      const int batch = 4; // 并发下载，最多 4 个一起
      for (int i = 0; i < entries.length; i += batch) {
        final List<MapEntry<String, String>> slice = entries.sublist(
          i,
          (i + batch).clamp(0, entries.length),
        );
        final List<Uint8List?> got = await Future.wait(
          slice.map(
            (MapEntry<String, String> e) => client.downloadBytes(e.value),
          ),
        );
        for (int j = 0; j < slice.length; j++) {
          final Uint8List? bytes = got[j];
          if (bytes != null && bytes.isNotEmpty) {
            assets[slice[j].key] = bytes;
          }
        }
      }
    } catch (_) {
      assets = <String, Uint8List>{};
    }

    final Set<String> missing = ids
        .where((String id) => !assets.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      // 兜底：老接口（base64 一次取回）
      try {
        assets.addAll(await client.fetchAssets(missing));
      } catch (_) {
        // 拿不到就保持引用，界面显示占位符
      }
    }
    return restoreAssets(remote, assets);
  }

  @override
  Future<void> save(Archive archive) async {
    try {
      // 先把大资源（头像/立绘/背景图/动态视频）上传到资源表，存档里只留引用。
      final AssetSplit split = splitAssets(archive);
      for (final AssetPayload asset in split.assets) {
        try {
          await client.uploadAsset(
            id: asset.id,
            bytes: asset.bytes,
            mime: asset.mime,
          );
        } catch (_) {
          // 单个资源失败不阻断整包保存（下次保存会重试，服务端按 id 去重）
        }
      }
      await client.putArchive(split.archive);
      _offline = false;
    } on Object {
      _offline = true;
      await fallback?.save(archive);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> clear() async {
    try {
      await client.deleteArchive();
    } on Object {
      _offline = true;
    }
    await fallback?.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> verifyPassword(String password) async {
    try {
      return await client.verifyPassword(password);
    } on Object {
      return false;
    }
  }

  void dispose() {
    _changes.close();
    client.close();
  }
}
