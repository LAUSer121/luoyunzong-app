import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/api_repository.dart';
import 'data/local_repository.dart';
import 'data/settings_store.dart';
import 'domain/repository.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsStore settings = SettingsStore();

  // 数据源：配置了服务端地址且开启云端同步 → 走 HTTP + MySQL（断网自动回落本地存档）。
  final String apiBase = await settings.apiBaseUrl();
  final bool useRemote = apiBase.isNotEmpty && await settings.useRemote();
  final LuoyunRepository repository = useRemote
      ? ApiRepository(
          client: ApiClient(baseUrl: apiBase, token: await settings.apiToken()),
          fallback: LocalRepository(),
        )
      : LocalRepository();

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
