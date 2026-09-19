/// 云同步引擎：本地 ⇄ 云端 双向同步。
///
/// 规则（简单、可预期、不丢数据）：
///   1. 云端没有存档 → 直接把本地推上去（本地不动）；
///   2. 内容完全一样 → 不传数据，只对齐时间戳；
///   3. 本地更新（改动时间更晚）→ 推送，覆盖前把云端那份留快照；
///   4. 云端更新 → 拉取，覆盖前把本地那份留快照；
///   5. 时间戳打平分不清谁新 → 以本机为准推上去，云端那份留快照。
///
/// 也就是说：**被覆盖掉的那一份永远先备份到本机快照**，界面上可一键恢复。
/// 快照写在本机（LocalRepository），「自动同步」开关与「上次同步时间」同样保存在
/// **本机设备**（SharedPreferences，见 SettingsStore），都不写进存档，
/// 所以不会跟着云端同步到别的设备。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_client.dart';
import '../data/api_repository.dart';
import '../data/direct_repository.dart';
import '../data/archive_codec.dart';
import '../data/asset_split.dart';
import '../domain/models.dart';

/// 云端网关抽象：便于单测替换。
abstract class CloudGateway {
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  fetchArchiveMeta();

  Future<void> putArchive(Archive archive);

  /// 清空云端存档（管理员「重置云端」）。
  Future<void> deleteArchive();

  /// 清空云端资源索引（可选），返回删掉的条数。
  Future<int> deleteAllAssets();
}

/// 云端不可达（网络问题），与「服务端返回错误」区分开。
class CloudUnreachable implements Exception {
  const CloudUnreachable(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
}

/// 基于 ApiRepository 的实现：上传会自动切分大资源（头像/立绘/背景），
/// 下载会自动还原资源引用，与普通保存走同一条链路。
class RepositoryCloudGateway implements CloudGateway {
  RepositoryCloudGateway({required this.repository, required this.client});

  final ApiRepository repository;
  final ApiClient client;

  @override
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  fetchArchiveMeta() async {
    try {
      return await repository.loadMeta();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }

  @override
  Future<void> putArchive(Archive archive) async {
    // ApiRepository.save 内部会兜底到本地，因此用 _offline 判断是否真的上传成功。
    await repository.save(archive);
    if (repository.isOffline) {
      throw const CloudUnreachable('云端写入失败');
    }
  }

  @override
  Future<void> deleteArchive() async {
    try {
      await client.deleteArchive();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }

  @override
  Future<int> deleteAllAssets() async {
    try {
      return await client.deleteAllAssets();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }
}

/// 直连模式的网关：App 直接读写 Aiven MySQL（没有中间服务器）。
class DirectCloudGateway implements CloudGateway {
  DirectCloudGateway(this.repository);

  final DirectRepository repository;

  @override
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  fetchArchiveMeta() async {
    try {
      return await repository.loadMeta();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }

  @override
  Future<void> putArchive(Archive archive) async {
    await repository.save(archive);
    if (repository.isOffline) {
      throw const CloudUnreachable('云端写入失败');
    }
  }

  @override
  Future<void> deleteArchive() async {
    try {
      await repository.clear();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }

  @override
  Future<int> deleteAllAssets() async {
    try {
      return await repository.deleteAllAssets();
    } on Object catch (e) {
      throw CloudUnreachable(e);
    }
  }
}

enum SyncAction {
  /// 未启用云端
  disabled,

  /// 已是最新
  upToDate,

  /// 本地 → 云端
  pushed,

  /// 云端 → 本地
  pulled,

  /// 内容不同但时间戳打平：保留本地，云端那份已备份到本地快照
  conflictKeptLocal,

  /// 网络/服务不可用
  offline,

  /// 出错
  error,
}

class SyncResult {
  const SyncResult(this.action, this.message);

  final SyncAction action;
  final String message;

  bool get ok =>
      action != SyncAction.offline &&
      action != SyncAction.error &&
      action != SyncAction.disabled;
}

class SyncManager extends ChangeNotifier {
  factory SyncManager({
    required CloudGateway? gateway,
    required Archive Function() readArchive,
    required Future<void> Function(Archive archive) applyArchive,
    required DateTime? Function() readLocalChangeAt,
    required Future<void> Function(DateTime at) markLocalSynced,
    required Future<void> Function(String json) writeSnapshot,
    required Future<String?> Function() readSnapshot,
    required Future<void> Function(bool enabled) persistAutoSync,
    required Future<void> Function(DateTime at) persistLastSyncAt,
  }) => SyncManager._(
    gateway,
    readArchive,
    applyArchive,
    readLocalChangeAt,
    markLocalSynced,
    writeSnapshot,
    readSnapshot,
    persistAutoSync,
    persistLastSyncAt,
  );

  SyncManager._(
    this._gateway,
    this._readArchive,
    this._applyArchive,
    this._readLocalChangeAt,
    this._markLocalSynced,
    this._writeSnapshot,
    this._readSnapshot,
    this._persistAutoSync,
    this._persistLastSyncAt,
  );

  final CloudGateway? _gateway;
  final Archive Function() _readArchive;
  final Future<void> Function(Archive archive) _applyArchive;
  final DateTime? Function() _readLocalChangeAt;
  final Future<void> Function(DateTime at) _markLocalSynced;
  final Future<void> Function(String json) _writeSnapshot;
  final Future<String?> Function() _readSnapshot;
  final Future<void> Function(bool enabled) _persistAutoSync;
  final Future<void> Function(DateTime at) _persistLastSyncAt;

  Timer? _timer;
  Timer? _debounce;

  bool _autoSync = false;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastMessage;
  SyncAction? _lastAction;

  bool get cloudAvailable => _gateway != null;
  bool get autoSync => _autoSync;
  bool get syncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastMessage => _lastMessage;
  SyncAction? get lastAction => _lastAction;

  /// 最近一次同步是否失败（用于界面标红）。
  bool get lastFailed =>
      _lastAction == SyncAction.offline || _lastAction == SyncAction.error;

  String get statusLabel {
    if (!cloudAvailable) return '未启用云端';
    if (_syncing) return '正在同步…';
    if (_lastSyncAt == null) return autoSync ? '自动同步已开启（尚未同步）' : '尚未同步';
    final String time = _formatTime(_lastSyncAt!);
    return '上次同步：$time${_lastMessage == null ? '' : ' · $_lastMessage'}';
  }

  /// 载入设备本地保存的开关与时间（不来自存档）。
  void restore({required bool autoSync, DateTime? lastSyncAt}) {
    _autoSync = autoSync;
    _lastSyncAt = lastSyncAt;
    if (_autoSync) _startTimer();
  }

  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    await _persistAutoSync(value);
    if (value) {
      _startTimer();
      // 打开就立刻对齐一次
      unawaited(syncNow());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(syncNow()),
    );
  }

  /// 本地有改动后调用：自动同步开启时延迟推送（合并短时间内的多次改动）。
  void onLocalChange() {
    if (!_autoSync || _gateway == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(syncNow()));
  }

  Future<SyncResult> syncNow() async {
    final CloudGateway? gateway = _gateway;
    if (gateway == null) {
      return const SyncResult(SyncAction.disabled, '未启用云端同步');
    }
    if (_syncing) {
      return SyncResult(_lastAction ?? SyncAction.upToDate, '正在同步，请稍候');
    }
    _syncing = true;
    notifyListeners();

    try {
      final ({Archive? archive, int revision, DateTime? updatedAt}) remote =
          await gateway.fetchArchiveMeta();
      final Archive local = _readArchive();
      final String localJson = _encode(local);
      final Archive? remoteArchive = remote.archive;
      final String? remoteJson = remoteArchive == null
          ? null
          : _encode(remoteArchive);
      final DateTime? localChangedAt = _readLocalChangeAt();
      final DateTime? remoteChangedAt = remote.updatedAt;

      // 1) 云端为空：直接推
      if (remoteJson == null) {
        await gateway.putArchive(local);
        await _markLocalSynced(DateTime.now());
        return _done(SyncAction.pushed, '已上传到云端（首次同步）');
      }

      // 两边内容完全一样：不需要传数据，只把时间戳对齐，避免来回空跑。
      //
      // 用「切分后的形态」比较：大资源在云端是 `asset:<内容哈希>` 引用，
      // 拉回来时会按字节重新拼 data URL（MIME 由内容嗅探得到），与本地原始
      // data URL 的 MIME 可能不完全一致。资源 id 是内容哈希，所以切分后
      // 同一份字节必然得到同一个引用 —— 这样比较不会因为 MIME 差异而误判。
      if (_encode(splitAssets(local).archive) ==
          _encode(splitAssets(remoteArchive!).archive)) {
        await _markLocalSynced(
          _newer(localChangedAt, remoteChangedAt) ?? DateTime.now(),
        );
        return _done(SyncAction.upToDate, '已是最新');
      }

      final bool localDirty =
          localChangedAt != null &&
          (remoteChangedAt == null || localChangedAt.isAfter(remoteChangedAt));
      final bool remoteDirty =
          remoteChangedAt != null &&
          (localChangedAt == null || remoteChangedAt.isAfter(localChangedAt));

      // 5) 时间戳打平（或双方都没记录改动时间）但内容不同：分不清谁更新，
      //    以本机为准推上去，并把云端那一份留快照，随时可恢复。
      if (!localDirty && !remoteDirty) {
        await _writeSnapshot(remoteJson);
        await gateway.putArchive(local);
        await _markLocalSynced(DateTime.now());
        return _done(
          SyncAction.conflictKeptLocal,
          '两边内容不同且时间相同，已保留本机版本（云端那份已备份）',
        );
      }
      // 2) 本地更新 → 推送（覆盖前先把云端旧版留快照）
      if (!remoteDirty) {
        await _writeSnapshot(remoteJson);
        await gateway.putArchive(local);
        await _markLocalSynced(DateTime.now());
        return _done(SyncAction.pushed, '已上传本地改动（云端旧版已备份）');
      }
      // 3) 云端更新 → 拉取（覆盖前先把本地旧版留快照）
      await _writeSnapshot(localJson);
      await _applyArchive(remoteArchive);
      await _markLocalSynced(remoteChangedAt);
      return _done(SyncAction.pulled, '已拉取云端更新（本地旧版已备份）');
    } catch (e) {
      // 网络类异常 → 归类为「云端不可达」，稍后自动重试；服务端明确报错才算失败。
      final bool unreachable = e is! ApiException;
      return _done(
        unreachable ? SyncAction.offline : SyncAction.error,
        unreachable ? '云端暂不可达，稍后会自动重试' : '同步失败：$e',
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // 管理员工具（仅解锁管理员后可调用；界面上都带二次确认）
  // ------------------------------------------------------------------

  /// 强制用本机存档覆盖云端（不看时间戳）。覆盖前把云端那份留成本机快照。
  Future<SyncResult> forcePushLocal() async {
    final CloudGateway? gateway = _gateway;
    if (gateway == null) {
      return const SyncResult(SyncAction.disabled, '未启用云端同步');
    }
    if (_syncing) return const SyncResult(SyncAction.pushed, '正在同步，请稍候');
    _syncing = true;
    notifyListeners();
    try {
      final ({Archive? archive, int revision, DateTime? updatedAt}) remote =
          await gateway.fetchArchiveMeta();
      final Archive? remoteArchive = remote.archive;
      if (remoteArchive != null) {
        // 先把云端旧版备份到本机，出事了还能捞回来
        await _writeSnapshot(_encode(remoteArchive));
      }
      await gateway.putArchive(_readArchive());
      await _markLocalSynced(DateTime.now());
      return _done(
        SyncAction.pushed,
        remoteArchive == null ? '已强制上传本机存档到云端' : '已用本机存档覆盖云端（云端旧版已备份到本机快照）',
      );
    } catch (e) {
      final bool unreachable = e is! ApiException;
      return _done(
        unreachable ? SyncAction.offline : SyncAction.error,
        unreachable ? '云端暂不可达，稍后自动重试' : '强制覆盖失败：$e',
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 强制用云端存档覆盖本机（不看时间戳）。覆盖前把本机那份留成本机快照。
  Future<SyncResult> forcePullRemote() async {
    final CloudGateway? gateway = _gateway;
    if (gateway == null) {
      return const SyncResult(SyncAction.disabled, '未启用云端同步');
    }
    if (_syncing) return const SyncResult(SyncAction.pulled, '正在同步，请稍候');
    _syncing = true;
    notifyListeners();
    try {
      final ({Archive? archive, int revision, DateTime? updatedAt}) remote =
          await gateway.fetchArchiveMeta();
      final Archive? remoteArchive = remote.archive;
      if (remoteArchive == null) {
        return _done(SyncAction.offline, '云端没有存档，无法覆盖本机');
      }
      await _writeSnapshot(_encode(_readArchive()));
      await _applyArchive(remoteArchive);
      await _markLocalSynced(remote.updatedAt ?? DateTime.now());
      return _done(SyncAction.pulled, '已用云端存档覆盖本机（本机旧版已备份）');
    } catch (e) {
      final bool unreachable = e is! ApiException;
      return _done(
        unreachable ? SyncAction.offline : SyncAction.error,
        unreachable ? '云端暂不可达，稍后自动重试' : '强制覆盖失败：$e',
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 重置云端：清空云端存档（可选连资源一起清），并把云端那份先备份到本机。
  ///
  /// 清空后会**自动关掉「自动同步」**，否则下一次轮询又把本机内容推上去。
  Future<SyncResult> resetCloud({bool includeAssets = false}) async {
    final CloudGateway? gateway = _gateway;
    if (gateway == null) {
      return const SyncResult(SyncAction.disabled, '未启用云端同步');
    }
    if (_syncing) return const SyncResult(SyncAction.upToDate, '正在同步，请稍候');
    _syncing = true;
    notifyListeners();
    try {
      final ({Archive? archive, int revision, DateTime? updatedAt}) remote =
          await gateway.fetchArchiveMeta();
      final Archive? remoteArchive = remote.archive;
      if (remoteArchive != null) await _writeSnapshot(_encode(remoteArchive));
      await gateway.deleteArchive();
      int assets = 0;
      if (includeAssets) assets = await gateway.deleteAllAssets();
      // 关掉自动同步，避免刚清空就被推回去
      if (_autoSync) await setAutoSync(false);
      return _done(
        SyncAction.upToDate,
        '云端已重置（存档已清空${includeAssets ? '，资源 $assets 条' : ''}'
        '，云端内容已备份到本机快照；自动同步已关闭）',
      );
    } catch (e) {
      final bool unreachable = e is! ApiException;
      return _done(
        unreachable ? SyncAction.offline : SyncAction.error,
        unreachable ? '云端暂不可达，稍后自动重试' : '重置云端失败：$e',
      );
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  static DateTime? _newer(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// 读取上一次同步留下的本地快照（冲突时保留的旧版本），供用户手动恢复。
  Future<Archive?> snapshotArchive() async {
    final String? text = await _readSnapshot();
    if (text == null || text.trim().isEmpty) return null;
    return ArchiveCodec.decode(text);
  }

  SyncResult _done(SyncAction action, String message) {
    _lastAction = action;
    _lastMessage = message;
    if (action != SyncAction.offline && action != SyncAction.error) {
      _lastSyncAt = DateTime.now();
      unawaited(_persistLastSyncAt(_lastSyncAt!));
    }
    notifyListeners();
    return SyncResult(action, message);
  }

  String _encode(Archive archive) => ArchiveCodec.encodeJson(archive);

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
