/// 默认音乐（不凡 —— 王铮亮，可改名称、可开关、随存档同步云端）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/features/settings/settings_page.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('模型', () {
    test('出厂默认音乐是不凡 —— 王铮亮，且默认开启', () {
      final BgmSetting bgm = BgmSetting();
      expect(bgm.useDefaultTrack, isTrue);
      expect(bgm.defaultTrackQuery, '不凡 王铮亮');
      expect(bgm.defaultTrack.name, '不凡');
      expect(bgm.defaultTrack.artist, '王铮亮');
      expect(bgm.defaultTrack.id, isNotEmpty, reason: '要能按 id 取播放地址');
      expect(bgm.trackCount, 1, reason: '默认音乐算一首');
      expect(bgm.defaultOffset, 1);
    });

    test('开关与名称都能存进存档并原样读回（这一步决定能不能同步到云端）', () {
      final BgmSetting bgm = BgmSetting()
        ..useDefaultTrack = false
        ..defaultTrackQuery = '沧海一声笑'
        ..defaultTrack = OnlineTrack(
          id: '123456',
          name: '沧海一声笑',
          artist: '许冠杰',
        );

      final Archive archive = Archive()..bgm = bgm;
      final Archive back = ArchiveCodec.decode(
        ArchiveCodec.encodeJson(archive),
      )!;

      expect(back.bgm.useDefaultTrack, isFalse);
      expect(back.bgm.defaultTrackQuery, '沧海一声笑');
      expect(back.bgm.defaultTrack.name, '沧海一声笑');
      expect(back.bgm.defaultTrack.artist, '许冠杰');
      expect(back.bgm.defaultTrack.id, '123456');
      expect(back.bgm.trackCount, 0, reason: '关掉后不占曲单位置');
    });

    test('老存档没有这些字段：自动补出厂默认并打开开关', () {
      final Map<String, Object?> legacy = <String, Object?>{
        'archiveVersion': 4,
        'bgm': <String, Object?>{
          'volume': 0.5,
          'customNames': <String>['旧曲子.mp3'],
          'onlineTracks': <Object?>[],
          'index': 0,
          'autoPlay': true,
        },
      };
      final Archive archive = Archive.fromJson(legacy);

      expect(archive.bgm.useDefaultTrack, isTrue);
      expect(archive.bgm.defaultTrack.name, '不凡');
      expect(archive.bgm.defaultTrackQuery, '不凡 王铮亮');
      expect(archive.bgm.trackCount, 2, reason: '默认音乐 + 一首旧曲子');
    });
  });

  group('曲单', () {
    testWidgets('开关打开时默认音乐排在曲单第一首，关掉后不再出现', (WidgetTester tester) async {
      final MemoryBackend backend = MemoryBackend();
      final AppState state = AppState(
        repository: LocalRepository(backend: backend),
      );
      await state.init();

      // 默认开启：曲单第一首就是默认音乐。
      expect(state.bgm.tracks.first.name, '不凡');
      expect(state.bgm.tracks.first.isOnline, isTrue);

      // 换成别的歌（模拟搜索选中）。
      state.setDefaultTrack(
        OnlineTrack(id: '999', name: '御剑江湖', artist: '某歌手'),
        query: '御剑江湖',
      );
      expect(state.bgm.tracks.first.name, '御剑江湖');

      // 关掉开关：默认音乐从曲单里消失。
      state.setUseDefaultTrack(false);
      expect(state.bgm.tracks.any((dynamic t) => t.name == '御剑江湖'), isFalse);
      expect(state.archive.bgm.useDefaultTrack, isFalse);
      await state.flush(); // 收掉 800ms 防抖定时器，避免测试结束时有挂起的 Timer
    });

    testWidgets('只输入名称、没搜到曲目时也能保存名称（供云端同步）', (WidgetTester tester) async {
      final AppState state = AppState(
        repository: LocalRepository(backend: MemoryBackend()),
      );
      await state.init();

      state.setDefaultTrackQuery('某首还没搜到的歌');
      expect(state.defaultTrackQuery, '某首还没搜到的歌');
      expect(state.defaultTrack.name, '不凡', reason: '没绑定新曲目时不乱改已有关联');
      await state.flush();
    });
  });

  testWidgets('设置页可以开关默认音乐、输入名称，并写进存档（随云同步）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final MemoryBackend backend = MemoryBackend();
    final AppState state = AppState(
      repository: LocalRepository(backend: backend),
    );
    await state.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // 卡片上有开关 + 名称输入框 + 按钮。
    expect(find.text('启用默认音乐'), findsOneWidget);
    expect(find.text('搜索并设为默认'), findsOneWidget);
    expect(find.textContaining('当前：不凡 · 王铮亮'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '默认音乐'), '测试歌名');
    await tester.pumpAndSettle();

    // 关掉开关 → 存档里立刻是 false（会被同步到云端）。
    final Finder switchFinder = find.text('启用默认音乐');
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(state.useDefaultTrack, isFalse);
    final String saved = backend.lastWritten ?? '';
    expect(saved, contains('"useDefaultTrack": false'));
    expect(saved, contains('不凡'), reason: '默认曲目信息也在存档里');
  });
}
