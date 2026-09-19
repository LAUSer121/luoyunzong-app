import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'data/api_client.dart';
import 'data/api_repository.dart';
import 'data/local_repository.dart';
import 'data/settings_store.dart';
import 'domain/repository.dart';
import 'state/app_state.dart';
import 'state/sync_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsStore settings = SettingsStore();

  final _Resolved resolved = await _resolveRepository(settings);
  final AppState state = AppState(
    repository: resolved.repository,
    localStore: resolved.local,
    settings: settings,
  );

  // 在线电台代理地址（可选）先加载，再初始化存档与曲单。
  state.setNeteaseBase(await settings.neteaseBase());
  await state.init();

  // 云同步：即使启动时探测失败也保留通道，稍后自动重试。
  final ApiRepository? cloud = resolved.cloud;
  final SyncManager sync = SyncManager(
    gateway: cloud == null
        ? null
        : RepositoryCloudGateway(repository: cloud, client: cloud.client),
    readArchive: () => state.archive,
    applyArchive: state.applyRemoteArchive,
    readLocalChangeAt: () => state.lastLocalChangeAt,
    markLocalSynced: state.markSyncedAt,
    writeSnapshot: state.writeSyncSnapshot,
    readSnapshot: state.readSyncSnapshot,
    persistAutoSync: settings.setAutoSync,
    persistLastSyncAt: settings.setLastSyncAt,
  );
  state.sync = sync;
  state.restoreLocalChangeAt(await settings.lastLocalChangeAt());
  sync.restore(
    autoSync: await settings.autoSync(),
    lastSyncAt: await settings.lastSyncAt(),
  );

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const LuoyunzongApp(),
    ),
  );
}

/// 数据源装配结果。
typedef _Resolved = ({
  LuoyunRepository repository,
  LocalRepository local,
  ApiRepository? cloud,
});

/// 选择数据源：
/// 1) 构建期烧入的云地址（AppConfig.apiCandidates）能连通 → 云端 + 本地兜底；
/// 2) 用户在设置里手动填过地址且开了开关（仅特殊打包会显示该入口）→ 同上；
/// 3) 都不通 → 先用本地存档，同时保留云端通道供自动/手动同步重试。
///
/// 全过程不在界面展示任何服务端/数据库信息。
Future<_Resolved> _resolveRepository(SettingsStore settings) async {
  final LocalRepository local = LocalRepository();

  final String savedBase = (await settings.apiBaseUrl()).trim();
  final String savedToken = (await settings.apiToken()).trim();
  final bool savedEnabled = await settings.useRemote();

  // 构建期配置优先；用户设置仅在允许显示配置的包里生效
  final List<({String base, String token})> candidates =
      <({String base, String token})>[
        for (final String base in AppConfig.apiCandidates)
          (base: base, token: AppConfig.apiToken),
        if (AppConfig.showServerConfig && savedEnabled && savedBase.isNotEmpty)
          (base: savedBase, token: savedToken),
      ];

  ApiRepository? offlineCloud;
  for (final ({String base, String token}) c in candidates) {
    final ApiClient client = ApiClient(baseUrl: c.base, token: c.token);
    final ApiRepository api = ApiRepository(client: client, fallback: local);
    if (await client.ping()) {
      return (repository: api, local: local, cloud: api);
    }
    // 第一个候选留作离线重试通道（不额外建连接，复用已建好的 client）。
    offlineCloud ??= api;
  }
  if (offlineCloud == null) {
    return (repository: local, local: local, cloud: null);
  }
  return (repository: local, local: local, cloud: offlineCloud);
}
