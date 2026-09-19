/// 真机联调用的云同步 E2E（默认跳过，CI 不会跑）。
///
/// 本地起服务端后手动执行：
///   $env:LUOYUNZONG_E2E='1'
///   $env:LUOYUNZONG_E2E_TOKEN='server/.env 里的 API_TOKEN'
///   flutter test test/e2e_sync_live_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/api_client.dart';
import 'package:luoyunzong/data/api_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/state/sync_manager.dart';

/// 约 60KB 的假「立绘」：超过 48KB 阈值，会被切分进资源表。
final String _portraitDataUrl =
    'data:image/png;base64,'
    '${base64Encode(List<int>.generate(60000, (int i) => (i * 7) % 251))}';

Archive _archive(String notice) {
  final Archive a = Archive()..notice = notice;
  a.memberList.add(Member(name: '测试弟子', role: '外门弟子'));
  a.memberList.first.portrait = _portraitDataUrl;
  return a;
}

void main() {
  final String? flag = Platform.environment['LUOYUNZONG_E2E'];
  final String token = Platform.environment['LUOYUNZONG_E2E_TOKEN'] ?? '';
  final String base =
      Platform.environment['LUOYUNZONG_E2E_BASE'] ?? 'http://127.0.0.1:8080';

  test('本地 ⇄ 云端双向同步（真实服务端）', () async {
    final ApiClient client = ApiClient(baseUrl: base, token: token);
    final ApiRepository repo = ApiRepository(client: client);

    // 从干净状态开始（服务端已有存档也无妨，下面第一步会按时间戳决定方向）。
    try {
      await client.deleteArchive();
    } on Object {
      // 没存档时 404，忽略
    }

    DateTime? localChange = DateTime(2026, 1, 1);
    Archive local = _archive('本机版本A');
    final List<Archive> applied = <Archive>[];
    final List<String> snapshots = <String>[];
    final List<DateTime> syncedAt = <DateTime>[];

    final SyncManager sync = SyncManager(
      gateway: RepositoryCloudGateway(repository: repo, client: client),
      readArchive: () => local,
      applyArchive: (Archive a) async {
        applied.add(a);
        local = a;
      },
      readLocalChangeAt: () => localChange,
      markLocalSynced: (DateTime at) async {
        syncedAt.add(at);
        localChange = DateTime(2026, 1, 1); // 视为「已同步、不再算本地新改动」
      },
      writeSnapshot: (String json) async => snapshots.add(json),
      readSnapshot: () async => snapshots.isEmpty ? null : snapshots.last,
      persistAutoSync: (bool v) async {},
      persistLastSyncAt: (DateTime at) async {},
    );

    // 1) 首次同步：云端为空 → 本地推上去（大资源应被切分成 asset 引用）。
    final SyncResult first = await sync.syncNow();
    expect(first.action, SyncAction.pushed, reason: first.message);
    final Archive? cloud1 = await client.fetchArchive();
    expect(cloud1, isNotNull);
    expect(cloud1!.notice, '本机版本A');
    expect(cloud1.memberList.first.portrait, startsWith('asset:'));
    stdout.writeln('[E2E] 1 首次上传 OK，立绘已切分为资源引用');

    // 2) 模拟另一台设备改了云端 → 本机没改 → 应拉取并先留快照。
    final Archive other = _archive('云端版本B')..motto = '来自另一台设备';
    await client.putArchive(other);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final SyncResult second = await sync.syncNow();
    expect(second.action, SyncAction.pulled, reason: second.message);
    expect(applied.single.notice, '云端版本B');
    expect(applied.single.motto, '来自另一台设备');
    expect(
      applied.single.memberList.first.portrait,
      _portraitDataUrl,
      reason: '立绘应从资源表还原',
    );
    expect(snapshots, hasLength(1), reason: '拉取前应备份被覆盖的本地版本');
    expect(snapshots.single, contains('本机版本A'));
    stdout.writeln('[E2E] 2 拉取云端更新 OK，本地旧版已快照，立绘已还原');

    // 3) 本机改动 → 应推送（并备份被覆盖的云端版本）。
    local = _archive('本机版本C');
    localChange = DateTime.now().add(const Duration(minutes: 1));
    final SyncResult third = await sync.syncNow();
    expect(third.action, SyncAction.pushed, reason: third.message);
    final Archive? cloud3 = await client.fetchArchive();
    expect(cloud3!.notice, '本机版本C');
    expect(snapshots.last, contains('云端版本B'));
    stdout.writeln('[E2E] 3 上传本机改动 OK，云端旧版已快照');

    // 4) 再来一次：内容一致 → 不做任何传输。
    final SyncResult fourth = await sync.syncNow();
    expect(fourth.action, SyncAction.upToDate, reason: fourth.message);
    stdout.writeln('[E2E] 4 幂等复查 OK（${fourth.message}）');

    // 5) 快照可恢复。
    final Archive? snapshot = await sync.snapshotArchive();
    expect(snapshot, isNotNull);
    expect(snapshot!.notice, '云端版本B');
    stdout.writeln('[E2E] 5 快照恢复读取 OK');

    expect(syncedAt, isNotEmpty);
    sync.dispose();
    client.close();
  }, skip: flag == '1' ? false : '需要本地服务端；设置 LUOYUNZONG_E2E=1 后运行');
}
