/// 设置页「云端同步」卡片的界面行为：
/// 自动同步开关、立即同步按钮、以及开关落在本机（不写进存档）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/core/constants.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/data/settings_store.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/features/settings/settings_page.dart';
import 'package:luoyunzong/state/app_state.dart';
import 'package:luoyunzong/state/sync_manager.dart';

import 'sync_manager_test.dart' show FakeGateway;
import 'widget_test.dart' show MemoryBackend;

Archive _archive(String notice) => Archive()..notice = notice;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('存在云通道时显示同步卡片，可立即同步与开关自动同步', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final MemoryBackend backend = MemoryBackend();
    final SettingsStore store = SettingsStore();
    final AppState state = AppState(
      repository: LocalRepository(backend: backend),
      localStore: LocalRepository(backend: backend),
      settings: store,
    );
    await state.init();

    Archive local = _archive('本机内容');
    DateTime? localChange = DateTime(2026, 1, 1);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('云端内容'),
      updatedAt: DateTime(2026, 6, 1),
    );

    final SyncManager sync = SyncManager(
      gateway: gateway,
      readArchive: () => local,
      applyArchive: (Archive a) async => local = a,
      readLocalChangeAt: () => localChange,
      markLocalSynced: (DateTime at) async => localChange = at,
      writeSnapshot: (String json) async {},
      readSnapshot: () async => null,
      // 真的写设备本地设置（SharedPreferences mock），验证开关落盘。
      persistAutoSync: store.setAutoSync,
      persistLastSyncAt: store.setLastSyncAt,
    );
    addTearDown(sync.dispose);
    state.sync = sync;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // 卡片与两个关键控件都在。
    expect(find.text('云端同步'), findsOneWidget);
    expect(find.text('自动同步云端'), findsOneWidget);
    expect(find.text('恢复上次同步前的备份'), findsOneWidget);

    // 立即同步：云端更新的场景 → 把云端内容拉回本机。
    final Finder syncButton = find.text('立即同步');
    await tester.ensureVisible(syncButton);
    await tester.pumpAndSettle();
    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(local.notice, '云端内容', reason: '云端更新时应拉取到本机');
    expect(find.textContaining('上次同步'), findsAtLeastNWidgets(1));

    // 自动同步开关：状态落到设备本地设置。
    final Finder autoSwitch = find.text('自动同步云端');
    await tester.ensureVisible(autoSwitch);
    await tester.pumpAndSettle();
    await tester.tap(autoSwitch);
    await tester.pumpAndSettle();

    expect(sync.autoSync, isTrue);
    expect(await store.autoSync(), isTrue, reason: '开关必须保存在本机设备');
    expect(await store.lastSyncAt(), isNotNull, reason: '上次同步时间也存本机');

    // 存档里不应出现任何同步开关字段（不能跟着云端跑到别的设备）。
    expect(backend.lastWritten, isNot(contains('auto_sync')));

    // 只读模式：管理员工具在那里，但按钮是禁用的
    expect(find.text('管理员工具'), findsOneWidget);
    final Finder pushOff = find.widgetWithText(OutlinedButton, '本机覆盖云端');
    await tester.ensureVisible(pushOff);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(pushOff).onPressed, isNull);

    // 关掉自动同步：取消 45s 轮询定时器，避免测试结束时有挂起的 Timer。
    await sync.setAutoSync(false);
  });

  testWidgets('管理员解锁后：强制覆盖 / 重置云端都要二次确认', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final MemoryBackend backend = MemoryBackend();
    final SettingsStore store = SettingsStore();
    final AppState state = AppState(
      repository: LocalRepository(backend: backend),
      localStore: LocalRepository(backend: backend),
      settings: store,
    );
    await state.init();
    state.unlock(kDefaultAdminPassword);

    Archive local = _archive('本机内容');
    DateTime? localChange = DateTime(2026, 1, 1);
    final FakeGateway gateway = FakeGateway(
      archive: _archive('云端内容'),
      updatedAt: DateTime(2030, 1, 1), // 云端“更新”，但强制覆盖应该推本机
    );
    final SyncManager sync = SyncManager(
      gateway: gateway,
      readArchive: () => local,
      applyArchive: (Archive a) async => local = a,
      readLocalChangeAt: () => localChange,
      markLocalSynced: (DateTime at) async => localChange = at,
      writeSnapshot: (String json) async {},
      readSnapshot: () async => null,
      persistAutoSync: store.setAutoSync,
      persistLastSyncAt: store.setLastSyncAt,
    );
    addTearDown(sync.dispose);
    state.sync = sync;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    final Finder pushButton = find.widgetWithText(OutlinedButton, '本机覆盖云端');
    await tester.ensureVisible(pushButton);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(pushButton).onPressed, isNotNull);

    // 点一下先出二次确认；取消则什么都不做
    await tester.tap(pushButton);
    await tester.pumpAndSettle();
    expect(find.text('用本机存档覆盖云端？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.puts, 0, reason: '取消后不应真的覆盖');

    // 确认后才真的推
    await tester.tap(pushButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖云端'));
    await tester.pumpAndSettle();
    expect(gateway.puts, 1);
    expect(gateway.archive!.notice, '本机内容');

    // 重置云端：确认弹窗里有「同时清空云端资源」勾选
    final Finder resetButton = find.widgetWithText(OutlinedButton, '重置云端');
    await tester.ensureVisible(resetButton);
    await tester.pumpAndSettle();
    await tester.tap(resetButton);
    await tester.pumpAndSettle();
    expect(find.text('重置云端？'), findsOneWidget);
    expect(find.textContaining('同时清空云端资源'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重置云端'));
    await tester.pumpAndSettle();

    expect(gateway.deletes, 1);
    expect(gateway.archive, isNull);
    expect(sync.autoSync, isFalse, reason: '重置后自动同步会被关掉');
  });
}
