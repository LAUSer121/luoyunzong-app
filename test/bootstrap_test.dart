/// 启动装配测试：云端不可达时仍要能纯本地使用，并且保留通道等恢复。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/core/bootstrap.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/data/settings_store.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/state/app_state.dart';
import 'package:luoyunzong/state/sync_manager.dart';

import 'widget_test.dart' show MemoryBackend;

/// 本机一个几乎肯定没人监听的端口，用来模拟「云端不可达」。
const String _deadUrl = 'http://127.0.0.1:9';

void main() {
  // AppState.init 会初始化 BGM 播放器，需要 Flutter 绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('没有候选地址：纯本地，不建云通道', () async {
    final ResolvedRepository resolved = await resolveRepository(
      candidates: const <String>[],
      local: LocalRepository(backend: MemoryBackend()),
    );

    expect(resolved.repository, isA<LocalRepository>());
    expect(resolved.cloud, isNull);
  });

  test('云端不可达：回落本地存档，但保留云通道等重试', () async {
    final ResolvedRepository resolved = await resolveRepository(
      candidates: const <String>[_deadUrl],
      local: LocalRepository(backend: MemoryBackend()),
    );

    // 仓储必须是本地：断网也要能正常用。
    expect(resolved.repository, isA<LocalRepository>());
    // 通道保留：设置页可以看到同步卡片，自动同步会定时重试。
    expect(resolved.cloud, isNotNull);

    final SettingsStore settings = SettingsStore();
    final AppState state = AppState(
      repository: resolved.repository,
      localStore: resolved.local,
      settings: settings,
    );
    await state.init();

    final SyncManager sync = await attachSync(
      state,
      settings: settings,
      cloud: resolved.cloud,
    );
    addTearDown(sync.dispose);

    expect(sync.cloudAvailable, isTrue);

    // 手动同步：云端不通 → 归类为「暂不可达」，本地数据分毫不动。
    state.mutate((Archive a) => a.notice = '本机内容');
    final SyncResult result = await sync.syncNow();
    expect(result.action, SyncAction.offline);
    expect(result.ok, isFalse);
    expect(state.archive.notice, '本机内容');
    expect(await settings.autoSync(), isFalse, reason: '默认不自动同步');
  });

  test('自动同步开关与上次同步时间保存在设备本地', () async {
    final ResolvedRepository resolved = await resolveRepository(
      candidates: const <String>[_deadUrl],
      local: LocalRepository(backend: MemoryBackend()),
    );
    final SettingsStore settings = SettingsStore();
    await settings.setAutoSync(true);
    await settings.setLastSyncAt(DateTime(2026, 9, 19, 10, 30));

    final AppState state = AppState(
      repository: resolved.repository,
      localStore: resolved.local,
      settings: settings,
    );
    await state.init();

    final SyncManager sync = await attachSync(
      state,
      settings: settings,
      cloud: resolved.cloud,
    );
    addTearDown(() async {
      await sync.setAutoSync(false); // 取消 45s 轮询，避免挂起的 Timer
      sync.dispose();
    });

    // 重启后开关仍然是开的（存在本机，不来自存档）。
    expect(sync.autoSync, isTrue);
    expect(sync.lastSyncAt, DateTime(2026, 9, 19, 10, 30));
    expect(sync.statusLabel, contains('上次同步'));
  });
}
