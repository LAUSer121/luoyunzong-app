import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/features/bgm/bgm_player.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

Future<AppState> _state() async {
  final AppState state = AppState(
    repository: LocalRepository(backend: MemoryBackend()),
  );
  await state.init();
  return state;
}

Widget _harness(AppState state) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: const BgmFab(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('展开面板后切歌，标题与来源即时刷新（监听 BgmController）', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final AppState state = await _state();
    await tester.pumpWidget(_harness(state));
    await tester.pump();

    // 展开悬浮面板：默认曲单里已经有「默认音乐」（不凡 —— 王铮亮）。
    await tester.tap(find.byType(InkWell).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('不凡'), findsOneWidget);
    expect(find.text('王铮亮'), findsOneWidget);

    // 加入一首在线曲目：应立刻反映到面板（曾经要重新展开才刷新）
    state.bgm.addOnlineTrack(
      OnlineTrack(id: '30352891', name: '御剑江湖', artist: '小骆'),
    );
    await tester.pump();
    expect(find.text('御剑江湖'), findsOneWidget);
    expect(find.text('小骆'), findsOneWidget);

    // 再切一首（模拟下一首）
    state.bgm.addOnlineTrack(
      OnlineTrack(id: '30352892', name: '牵丝戏', artist: '银临'),
    );
    await tester.pump();
    expect(find.text('牵丝戏'), findsOneWidget);
  });

  testWidgets('在线曲目时长兜底：进度条刻度使用元数据时长', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final AppState state = await _state();
    await tester.pumpWidget(_harness(state));
    await tester.pump();
    await tester.tap(find.byType(InkWell).first);
    await tester.pump(const Duration(milliseconds: 300));

    state.bgm.addOnlineTrack(
      OnlineTrack(id: '1', name: '测试曲', durationMs: 239000),
    );
    await tester.pump();

    // 播放器没上报时长时，用元数据兜底 → 右侧总时长显示 3:59
    await state.bgm.playIndex(state.bgm.tracks.length - 1);
    await tester.pump();
    expect(state.bgm.effectiveDuration.inSeconds, 239);
    expect(find.text('3:59'), findsWidgets);
  });
}
