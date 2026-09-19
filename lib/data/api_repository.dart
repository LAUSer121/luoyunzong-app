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
      final Archive? remote = await client.fetchArchive();
      _offline = false;
      if (remote == null) return null;
      // 存档里的大资源以 `asset:<id>` 引用存在，按需从服务端资源表还原成 data URL。
      final Set<String> ids = referencedAssetIds(remote);
      if (ids.isEmpty) return remote;
      final Map<String, Uint8List> assets = await client.fetchAssets(ids);
      return restoreAssets(remote, assets);
    } on Object {
      _offline = true;
      return fallback?.load();
    }
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
