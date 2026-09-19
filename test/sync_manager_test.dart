/// 云同步引擎单测：本地 ⇄ 云端 的四种走向与冲突处理。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/state/sync_manager.dart';

/// 假网关：内存里放一份「云端存档」。
class FakeGateway implements CloudGateway {
  FakeGateway({this.archive, this.updatedAt});

  Archive? archive;
  DateTime? updatedAt;
  int puts = 0;
  Archive? lastPut;

  /// 设为非空则模拟云端不可达。
  Object? failure;

  @override
  Future<({Archive? archive, int revision, DateTime? updatedAt})>
  fetchArchiveMeta() async {
    final Object? f = failure;
    if (f != null) throw f;
    return (archive: archive, revision: puts, updatedAt: updatedAt);
  }

  @override
  Future<void> putArchive(Archive archive) async {
    final Object? f = failure;
    if (f != null) throw f;
    puts++;
    lastPut = archive;
    this.archive = archive;
    updatedAt = DateTime.now().add(const Duration(seconds: 1));
  }
}

/// 构造一份可区分的存档（用公告内容区分版本）。
Archive _archive(String notice) => Archive()..notice = notice;

SyncManager _manager({
  required FakeGateway gateway,
  required Archive Function() readArchive,
  required List<Archive> applied,
  required List<String> snapshots,
  DateTime? Function()? readLocalChangeAt,
  List<bool>? autoSyncLog,
  List<DateTime>? syncLog,
}) {
  return SyncManager(
    gateway: gateway,
    readArchive: readArchive,
    applyArchive: (Archive a) async => applied.add(a),
    readLocalChangeAt: readLocalChangeAt ?? () => null,
    markLocalSynced: (DateTime at) async => syncLog?.add(at),
    writeSnapshot: (String json) async => snapshots.add(json),
    readSnapshot: () async => snapshots.isEmpty ? null : snapshots.last,
    persistAutoSync: (bool v) async => autoSyncLog?.add(v),
    persistLastSyncAt: (DateTime at) async {},
  );
}

void main() {
  test('云端为空时把本地整包推上去', () async {
    final FakeGateway gateway = FakeGateway();
    final Archive local = _archive('本地');
    final List<String> snapshots = <String>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: <Archive>[],
      snapshots: snapshots,
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.pushed);
    expect(gateway.puts, 1);
    expect(snapshots, isEmpty);
    sync.dispose();
  });

  test('两边内容一致时不做任何传输', () async {
    final Archive local = _archive('一致');
    final FakeGateway gateway = FakeGateway(
      archive: ArchiveCodec.decode(ArchiveCodec.encodeJson(local)),
      updatedAt: DateTime.now(),
    );
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: <Archive>[],
      snapshots: <String>[],
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.upToDate);
    expect(gateway.puts, 0);
    sync.dispose();
  });

  test('只有本地改过 → 推送', () async {
    final DateTime remoteAt = DateTime(2026, 1, 1, 8);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('旧云端'),
      updatedAt: remoteAt,
    );
    final Archive local = _archive('新本地');
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: <Archive>[],
      snapshots: <String>[],
      readLocalChangeAt: () => remoteAt.add(const Duration(minutes: 5)),
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.pushed);
    expect(gateway.puts, 1);
    expect(gateway.archive!.notice, '新本地');
    sync.dispose();
  });

  test('只有云端改过 → 拉取，并先把本地存一份快照', () async {
    final DateTime localAt = DateTime(2026, 1, 1, 8);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('新云端'),
      updatedAt: localAt.add(const Duration(hours: 2)),
    );
    final Archive local = _archive('旧本地');
    final List<Archive> applied = <Archive>[];
    final List<String> snapshots = <String>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: applied,
      snapshots: snapshots,
      readLocalChangeAt: () => localAt,
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.pulled);
    expect(applied.single.notice, '新云端');
    expect(gateway.puts, 0);
    expect(snapshots.single, contains('旧本地'));
    sync.dispose();
  });

  test('本地更新 → 推送并备份被覆盖的云端旧版', () async {
    final DateTime base = DateTime(2026, 1, 1, 8);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('旧云端'),
      updatedAt: base.add(const Duration(minutes: 1)),
    );
    final Archive local = _archive('新本地');
    final List<String> snapshots = <String>[];
    final List<Archive> applied = <Archive>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: applied,
      snapshots: snapshots,
      readLocalChangeAt: () => base.add(const Duration(hours: 1)),
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.pushed);
    expect(gateway.puts, 1);
    expect(applied, isEmpty);
    expect(snapshots.single, contains('旧云端'));
    sync.dispose();
  });

  test('时间戳打平但内容不同 → 保留本机版本并备份云端那份', () async {
    final DateTime same = DateTime(2026, 1, 1, 8);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('云端版本'),
      updatedAt: same,
    );
    final Archive local = _archive('本机版本');
    final List<String> snapshots = <String>[];
    final List<Archive> applied = <Archive>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => local,
      applied: applied,
      snapshots: snapshots,
      readLocalChangeAt: () => same,
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.conflictKeptLocal);
    expect(gateway.puts, 1);
    expect(gateway.lastPut!.notice, '本机版本');
    expect(applied, isEmpty);
    expect(snapshots.single, contains('云端版本'));
    sync.dispose();
  });

  test('云端不可达 → 标记离线且不改动本地', () async {
    final FakeGateway gateway = FakeGateway()
      ..failure = const CloudUnreachable('断网');
    final List<Archive> applied = <Archive>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => _archive('本地'),
      applied: applied,
      snapshots: <String>[],
      readLocalChangeAt: () => DateTime(2026, 1, 1),
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.offline);
    expect(r.ok, isFalse);
    expect(sync.lastFailed, isTrue);
    expect(applied, isEmpty);
    expect(gateway.puts, 0);
    sync.dispose();
  });

  test('未配置云端时同步为 no-op', () async {
    final SyncManager sync = SyncManager(
      gateway: null,
      readArchive: () => _archive('本地'),
      applyArchive: (Archive a) async {},
      readLocalChangeAt: () => null,
      markLocalSynced: (DateTime at) async {},
      writeSnapshot: (String json) async {},
      readSnapshot: () async => null,
      persistAutoSync: (bool v) async {},
      persistLastSyncAt: (DateTime at) async {},
    );

    final SyncResult r = await sync.syncNow();

    expect(r.action, SyncAction.disabled);
    expect(sync.cloudAvailable, isFalse);
    expect(sync.statusLabel, '未启用云端');
    sync.dispose();
  });

  test('自动同步开关写回设备本地并在开启时立即对齐一次', () async {
    final FakeGateway gateway = FakeGateway();
    final List<bool> autoSyncLog = <bool>[];
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => _archive('本地'),
      applied: <Archive>[],
      snapshots: <String>[],
      autoSyncLog: autoSyncLog,
    );

    await sync.setAutoSync(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(autoSyncLog, <bool>[true]);
    expect(sync.autoSync, isTrue);
    expect(gateway.puts, 1); // 开启即同步一次

    await sync.setAutoSync(false);
    expect(autoSyncLog, <bool>[true, false]);
    expect(sync.autoSync, isFalse);
    sync.dispose();
  });

  test('自动同步关闭时本地改动不触发推送', () async {
    final FakeGateway gateway = FakeGateway(archive: _archive('云端'));
    final SyncManager sync = _manager(
      gateway: gateway,
      readArchive: () => _archive('本地'),
      applied: <Archive>[],
      snapshots: <String>[],
    );

    sync.onLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(gateway.puts, 0);
    sync.dispose();
  });
}
