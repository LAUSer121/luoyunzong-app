/// 回归：宗门任务页「收起 → 再展开」不能白屏。
///
/// 以前用 ExpansionTile + PageStorageKey，收起再展开出现过整页空白；
/// 现在改成自己控制的展开状态，这里用「像素亮度」直接卡住白屏：
/// 渲染后统计画面里接近白色的像素比例，白屏会接近 100%，正常深色界面远低于它。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:luoyunzong/core/constants.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/features/tasks/tasks_page.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

/// 不调用 `state.init()`：测试环境没有音频插件，这里只关心任务页渲染。
AppState _state({bool unlocked = false}) {
  final AppState state = AppState(
    repository: LocalRepository(backend: MemoryBackend()),
  );
  if (unlocked) state.unlock(kDefaultAdminPassword);
  return state;
}

final GlobalKey _shotKey = GlobalKey();

Future<void> _pump(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(key: _shotKey, child: const TasksPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 收起 → 再展开来回两遍，并断言没有任何异常。
Future<void> _toggleTwice(WidgetTester tester) async {
  expect(find.text('全部收起'), findsOneWidget, reason: '默认应全部展开');
  await tester.tap(find.text('全部收起'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.text('全部展开'), findsOneWidget);

  await tester.tap(find.text('全部展开'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.textContaining('录入'), findsWidgets, reason: '展开后录入框要回来');

  await tester.tap(find.text('全部收起'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('全部展开'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// 截图并返回「接近白色的像素占比」（白屏时接近 1）。
Future<double> _whiteRatio(WidgetTester tester, String savePath) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
  final ui.Image? image = await tester.runAsync(() => boundary.toImage());
  if (image == null) return 0;
  final ByteData? data = await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  if (data == null) return 0;

  final Uint8List bytes = data.buffer.asUint8List();
  int white = 0;
  int total = 0;
  for (int i = 0; i + 3 < bytes.length; i += 4) {
    final int r = bytes[i];
    final int g = bytes[i + 1];
    final int b = bytes[i + 2];
    total++;
    if (r > 200 && g > 200 && b > 200) white++;
  }
  try {
    File(savePath).writeAsBytesSync(bytes, flush: true);
  } catch (_) {
    // 截图只是留档，失败不影响断言。
  }
  return total == 0 ? 0 : white / total;
}

void main() {
  testWidgets('只读模式：收起再展开不白屏、录入框还在', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, _state());
    expect(find.text('天级任务'), findsOneWidget);
    await _toggleTwice(tester);

    // 单张卡片也试一遍（点标题行折叠 / 展开）。
    await tester.tap(find.text('天级任务'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('录入天级任务'), findsNothing, reason: '收起后内容应隐藏');
    await tester.tap(find.text('天级任务'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('录入天级任务'), findsOneWidget);

    final double white = await _whiteRatio(
      tester,
      'build/tasks_reexpand_locked.rgba',
    );
    expect(white, lessThan(0.10), reason: '接近白色的像素应很少（白屏会接近 1）');
  });

  testWidgets('解锁编辑模式：收起再展开不白屏', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, _state(unlocked: true));
    await _toggleTwice(tester);

    final double white = await _whiteRatio(
      tester,
      'build/tasks_reexpand_unlocked.rgba',
    );
    expect(white, lessThan(0.10), reason: '接近白色的像素应很少（白屏会接近 1）');
  });
}
