/// 背景相册：导入本地照片 → 存进存档（随云同步）→ 点缩略图切换；以及「显示原名」开关。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/data/asset_split.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/features/roster/roster_page.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

/// 造一张「大」照片（>48KB 阈值，会被切分进资源表）。
String _bigPhoto(int seed) {
  final List<int> bytes = List<int>.generate(
    60000,
    (int i) => (i * seed) % 251,
  );
  return 'data:image/jpeg;base64,${base64Encode(bytes)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('背景相册能存进存档并原样读回（这一步决定能不能同步到云端）', () {
    final String photo = _bigPhoto(7);
    final Archive archive = Archive()
      ..background = BackgroundSetting(
        type: BgType.image,
        data: photo,
        gallery: <String>[photo],
      );

    final Archive back = ArchiveCodec.decode(ArchiveCodec.encodeJson(archive))!;
    expect(back.background.gallery, hasLength(1));
    expect(back.background.gallery.single, photo);
    expect(back.background.data, photo);

    // 老存档没有 gallery 字段：默认空数组，不炸
    final Archive legacy = Archive.fromJson(<String, Object?>{
      'archiveVersion': 4,
      'background': <String, Object?>{'type': 'default'},
    });
    expect(legacy.background.gallery, isEmpty);
  });

  test('相册照片会被切分成资源引用并还原（云同步走这条路）', () {
    final String photo = _bigPhoto(11);
    final Archive archive = Archive()
      ..background = BackgroundSetting(
        type: BgType.image,
        data: photo,
        gallery: <String>[photo],
      );

    final AssetSplit split = splitAssets(archive);
    final List<String> refs = split.archive.background.gallery;
    expect(refs.single, startsWith('asset:'), reason: '大图应该只留引用');
    // 引用收集是给「已经切分过的存档」用的（用于批量拉取资源）
    expect(
      referencedAssetIds(split.archive),
      contains(assetRefId(refs.single)),
    );

    final Map<String, Uint8List> payloads = <String, Uint8List>{
      for (final AssetPayload p in split.assets) p.id: p.bytes,
    };
    final Archive restored = restoreAssets(split.archive, payloads);
    final String restoredPhoto = restored.background.gallery.single;
    // MIME 是按字节嗅探出来的，可能和原始 data URL 的 MIME 不同，
    // 所以比对「解码后的字节数」，而不是字符串长度。
    expect(
      base64Decode(restoredPhoto.split(',').last).length,
      base64Decode(photo.split(',').last).length,
    );
    expect(restored.background.data, restoredPhoto);
  });

  test('导入 / 切换 / 删除：相册最多留 12 张，删掉当前那张会回落到默认背景', () {
    final AppState state = AppState(
      repository: LocalRepository(backend: MemoryBackend()),
    );

    for (int i = 0; i < 14; i++) {
      state.addBackgroundPhoto('data:image/jpeg;base64,AAAA$i', apply: false);
    }
    expect(state.archive.background.gallery, hasLength(12), reason: '上限 12 张');

    final String first = state.archive.background.gallery.first;
    state.selectBackgroundPhoto(first);
    expect(state.archive.background.data, first);
    expect(state.archive.background.type, BgType.image);

    state.removeBackgroundPhoto(first);
    expect(state.archive.background.gallery, isNot(contains(first)));
    expect(state.archive.background.type, isNull, reason: '删的是当前背景 → 回落默认');
  });

  testWidgets('「显示原名」开关可切换，且只存本机（默认开）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final MemoryBackend backend = MemoryBackend();
    final AppState state = AppState(
      repository: LocalRepository(backend: backend),
      settings: null,
    );
    state.archive.memberList.add(
      Member(name: '韩立', role: '内门弟子', remark: '韩天尊'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: RosterPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.showOriginalName, isTrue, reason: '默认显示原名');
    expect(find.text('原名：韩立'), findsOneWidget);
    expect(find.text('显示原名'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(state.showOriginalName, isFalse);
    expect(find.text('原名：韩立'), findsNothing, reason: '关掉后不再显示原名行');
    expect(find.text('韩天尊'), findsOneWidget, reason: '备注仍然是姓名');
  });
}
