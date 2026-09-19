/// 人物备注：管理员可改、随存档同步云端；未解锁时拒绝修改。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luoyunzong/core/constants.dart';
import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/features/roster/roster_page.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

/// 不调用 init()：测试环境没有音频插件，这里只看数据与界面。
AppState _state({bool unlocked = false}) {
  final AppState state = AppState(
    repository: LocalRepository(backend: MemoryBackend()),
  );
  if (unlocked) state.unlock(kDefaultAdminPassword);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('备注能存进存档并原样读回（这一步决定能不能同步到云端）', () {
    final Archive archive = Archive()
      ..memberList.add(Member(name: '韩立', role: '内门弟子', remark: '擅长炼丹，已闭关三年'));

    final Archive back = ArchiveCodec.decode(ArchiveCodec.encodeJson(archive))!;
    expect(back.memberList.single.remark, '擅长炼丹，已闭关三年');

    // 老存档没有 remark 字段：默认空字符串，不炸。
    final Archive legacy = Archive.fromJson(<String, Object?>{
      'archiveVersion': 4,
      'memberList': <Object?>[
        <String, Object?>{'name': '旧人', 'role': '外门弟子'},
      ],
    });
    expect(legacy.memberList.single.remark, '');
  });

  test('未解锁（非管理员）不能改备注', () {
    final AppState state = _state();
    state.archive.memberList.add(Member(name: '张三', role: '外门弟子'));

    final bool ok = state.setMemberRemark('张三', '偷偷改一下');

    expect(ok, isFalse, reason: '只读模式必须拒绝');
    expect(state.archive.memberList.single.remark, isEmpty);
  });

  test('管理员可以改备注，且两端空格会被去掉', () {
    final AppState state = _state(unlocked: true);
    state.archive.memberList.add(Member(name: '张三', role: '外门弟子'));

    expect(state.setMemberRemark('张三', '  掌门亲传  '), isTrue);
    expect(state.archive.memberList.single.remark, '掌门亲传');
  });

  testWidgets('只读模式：名单只显示备注，没有修改入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final AppState state = _state();
    state.archive.memberList.add(
      Member(name: '韩立', role: '内门弟子', remark: '擅长炼丹'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: RosterPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('备注'), findsOneWidget, reason: '表头要有备注列');
    expect(find.text('擅长炼丹'), findsOneWidget, reason: '备注要显示出来');
    expect(find.text('修改'), findsNothing, reason: '未解锁时没有修改按钮');
  });

  testWidgets('管理员在「修改」弹窗里能改备注并保存', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final AppState state = _state(unlocked: true);
    state.archive.memberList.add(Member(name: '韩立', role: '内门弟子'));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: RosterPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    // 弹窗里有备注输入框 + 更换头像 / 立绘入口。
    expect(find.text('备注（仅管理员可改）'), findsOneWidget);
    expect(find.text('更换头像'), findsOneWidget);
    expect(find.text('立绘 / 视频'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '备注（仅管理员可改）'),
      '首席炼丹师',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.archive.memberList.single.remark, '首席炼丹师');
    expect(find.text('首席炼丹师'), findsWidgets, reason: '保存后表格里应显示备注');

    await state.flush(); // 收掉 800ms 防抖定时器
  });
}
