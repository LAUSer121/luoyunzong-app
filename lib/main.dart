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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsStore settings = SettingsStore();

  final LuoyunRepository repository = await _resolveRepository(settings);
  final AppState state = AppState(repository: repository);

  // 在线电台代理地址（可选）先加载，再初始化存档与曲单。
  state.setNeteaseBase(await settings.neteaseBase());
  await state.init();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const LuoyunzongApp(),
    ),
  );
}

/// 选择数据源：
/// 1) 构建期烧入的云地址（AppConfig.apiBase）能连通 → 云端 + 本地兜底；
/// 2) 用户在设置里手动填过地址且开了开关（仅特殊打包会显示该入口）→ 同上；
/// 3) 否则本地存档。
///
/// 全过程不在界面展示任何服务端/数据库信息。
Future<LuoyunRepository> _resolveRepository(SettingsStore settings) async {
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

  for (final ({String base, String token}) c in candidates) {
    final ApiClient client = ApiClient(baseUrl: c.base, token: c.token);
    if (await client.ping()) {
      return ApiRepository(client: client, fallback: local);
    }
    client.close();
  }
  return local;
}
