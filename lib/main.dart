import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/settings_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppState state = AppState();
  final SettingsStore settings = SettingsStore();
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
