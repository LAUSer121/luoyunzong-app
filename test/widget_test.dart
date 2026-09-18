import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:luoyunzong/app.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/data/storage_backend.dart';
import 'package:luoyunzong/state/app_state.dart';

/// 内存存储后端：测试中不触碰真实文件 / 浏览器存储。
class MemoryBackend implements StorageBackend {
  String? _data;

  @override
  String get description => '内存';

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async => _data = data;

  @override
  Future<void> delete() async => _data = null;

  @override
  Future<String?> location() async => null;
}

void main() {
  testWidgets('应用外壳可渲染并展示宗门名单页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final AppState state = AppState(
      repository: LocalRepository(backend: MemoryBackend()),
    );
    await state.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const LuoyunzongApp(),
      ),
    );
    // 应用内含加载态与动画，用有限帧推进比 pumpAndSettle 更稳。
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('落云宗'), findsWidgets);
    expect(find.text('宗门名单'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
