import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/bootstrap.dart';
import 'data/settings_store.dart';
import 'state/app_state.dart';
import 'state/sync_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsStore settings = SettingsStore();

  final ResolvedRepository resolved = await resolveRepositoryFromSettings(
    settings,
  );
  final AppState state = AppState(
    repository: resolved.repository,
    localStore: resolved.local,
    settings: settings,
  );

  // 在线电台代理地址（可选）先加载，再初始化存档与曲单。
  state.setNeteaseBase(await settings.neteaseBase());
  await state.init();

  // 云同步：即使启动时探测失败也保留通道，稍后自动重试。
  final SyncManager sync = await attachSync(
    state,
    settings: settings,
    cloud: resolved.cloud,
  );
  // 开关本来就开着的话，启动后再对齐一次（存档已加载完，不会停在旧数据上）。
  if (sync.autoSync) {
    unawaited(sync.syncNow());
  }

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const LuoyunzongApp(),
    ),
  );
}
