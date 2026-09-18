import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/core/constants.dart';
import 'package:luoyunzong/core/parsers.dart';
import 'package:luoyunzong/data/local_repository.dart';
import 'package:luoyunzong/domain/models.dart';
import 'package:luoyunzong/state/app_state.dart';

import 'widget_test.dart' show MemoryBackend;

Future<AppState> _state() async {
  final AppState state = AppState(
    repository: LocalRepository(backend: MemoryBackend()),
  );
  await state.init();
  return state;
}

void main() {
  // 纯 Dart 测试里也需要绑定，避免插件通道在构造期抛错（例如音频/路径插件）。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认只读，密码正确后可解锁并锁定', () async {
    final AppState s = await _state();
    expect(s.unlocked, isFalse);
    expect(s.unlock('错误密码'), isFalse);
    expect(s.unlocked, isFalse);
    expect(s.unlock(kDefaultAdminPassword), isTrue);
    expect(s.unlocked, isTrue);
    s.lock();
    expect(s.unlocked, isFalse);
  });

  test('修改密码校验旧密码、长度与一致性', () async {
    final AppState s = await _state();
    expect(s.changePassword('错的', 'newpass', 'newpass'), '旧密码不正确');
    expect(s.changePassword(kDefaultAdminPassword, '123', '123'), '新密码至少 4 位');
    expect(
      s.changePassword(kDefaultAdminPassword, 'newpass', 'other'),
      '两次输入的新密码不一致',
    );
    expect(
      s.changePassword(kDefaultAdminPassword, 'newpass', 'newpass'),
      isNull,
    );
    expect(s.archive.adminPassword, 'newpass');
  });

  test('录入成员并按职务权重排序，凡人不设境界', () async {
    final AppState s = await _state();
    s.addMember(name: '张三', role: '外门弟子', mainRank: '炼气', subRank: '前期');
    s.addMember(name: '李四', role: '宗主', mainRank: '炼虚', subRank: '大圆满');
    s.addMember(name: '王五', role: '凡人', mainRank: '炼气', subRank: '后期');
    expect(s.archive.memberList.map((Member m) => m.name), <String>[
      '李四',
      '张三',
      '王五',
    ]);
    final Member mortal = s.archive.memberByName('王五')!;
    expect(mortal.mainRank, kMortalRealm);
    expect(mortal.subRank, '');
  });

  test('批量导入跳过同名', () async {
    final AppState s = await _state();
    final MemberParseResult first = s.importMembers('云逍遥 宗主 炼虚大圆满');
    expect(first.added.length, 1);
    final MemberParseResult second = s.importMembers('云逍遥 长老\n林晚晴，长老，元婴后期');
    expect(second.added.length, 1);
    expect(second.duplicated, <String>['云逍遥']);
  });

  test('删除成员会清理通天塔记录与山峰归属', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.addMember(name: '乙', role: '外门弟子', mainRank: '筑基', subRank: '前期');
    expect(s.createPeak(name: '落云峰', leader: '甲'), isNull);
    expect(s.addPeakMember('落云峰', '乙'), isNull);
    expect(s.addTowerRecord('乙', 30), isNull);

    s.deleteMember('乙');
    expect(s.archive.towerList, isEmpty);
    expect(s.archive.peakList.single.members.length, 1);
  });

  test('山峰容量上限与唯一归属', () async {
    final AppState s = await _state();
    for (int i = 0; i < 9; i++) {
      s.addMember(name: '弟子$i', role: '外门弟子', mainRank: '炼气', subRank: '前期');
    }
    expect(s.createPeak(name: '甲峰', leader: '弟子0'), isNull);
    expect(s.createPeak(name: '乙峰', leader: '弟子8'), isNull);
    for (int i = 1; i < 7; i++) {
      expect(s.addPeakMember('甲峰', '弟子$i'), isNull);
    }
    expect(s.archive.peakList.first.members.length, kPeakCapacity);
    expect(s.addPeakMember('甲峰', '弟子7'), '该峰已达 $kPeakCapacity 人上限');
    expect(s.addPeakMember('乙峰', '弟子1'), '该弟子已归属山峰「甲峰」，每人只能归属一座山峰');
    expect(s.removePeakMember('甲峰', '弟子0'), '峰主不可移除，请先改任峰主');
  });

  test('通天塔榜首唯一且同步兼任徽章', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.addMember(name: '乙', role: '内门弟子', mainRank: '筑基', subRank: '中期');
    s.addTowerRecord('甲', 10);
    s.addTowerRecord('乙', 20);
    s.setTowerChampion('甲');
    expect(s.archive.towerList.first.name, '甲');
    expect(s.archive.towerList.first.isChampion, isTrue);
    expect(s.archive.memberByName('甲')!.subRoles, contains(kChampionTitle));

    s.setTowerChampion('乙');
    expect(
      s.archive.towerList.where((TowerRecord t) => t.isChampion).length,
      1,
    );
    expect(
      s.archive.memberByName('甲')!.subRoles,
      isNot(contains(kChampionTitle)),
    );

    s.unsetTowerChampion('乙');
    expect(s.archive.towerList.any((TowerRecord t) => t.isChampion), isFalse);
    expect(
      s.archive.memberByName('乙')!.subRoles,
      isNot(contains(kChampionTitle)),
    );
  });

  test('成绩场次：导入、同名拒绝、未匹配跳过、阈值保存', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.addMember(name: '乙', role: '外门弟子', mainRank: '筑基', subRank: '前期');

    final String msg = s.importScoresFromText(
      name: '三月演武',
      text: '甲 90\n乙 55\n幽灵 80\n',
    );
    expect(msg.contains('成功 2 条'), isTrue);
    expect(msg.contains('幽灵'), isTrue);
    expect(s.archive.examData.sessions.single.records.length, 2);

    final String dup = s.importScoresFromText(name: '三月演武', text: '甲 100');
    expect(dup.startsWith('失败'), isTrue);
    expect(s.archive.examData.sessions.length, 1);

    s.saveThreshold(70, 95);
    expect(s.archive.examData.threshold, 70);
    expect(s.archive.examData.thresholdExcellent, 95);
  });

  test('手动补录成绩覆盖同名记录', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.newExamSession(name: '测试场');
    s.addExamRecord('甲', 60);
    s.addExamRecord('甲', 88);
    expect(s.archive.examData.current!.records.length, 1);
    expect(s.archive.examData.current!.records.single.score, 88);
  });

  test('曲面任务条件可保存，公告与宗旨可编辑', () async {
    final AppState s = await _state();
    s.setTaskConditions(TaskGrade.tian, <String>['宗主']);
    expect(s.archive.taskConditions['tian'], <String>['宗主']);
    s.setNotice('宗门公告内容');
    s.setUpdateText('更新内容');
    s.setMotto('   ');
    expect(s.archive.notice, '宗门公告内容');
    expect(s.archive.updateText, '更新内容');
    expect(s.archive.motto, kDefaultMotto);
  });

  test('存档可导出再导入并保留数据', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.setBackgroundPreset('jade');
    final String json = s.exportJson();

    final AppState s2 = await _state();
    expect(s2.importArchiveText(json), isNull);
    expect(s2.archive.memberList.single.name, '甲');
    expect(s2.archive.background.type, BgType.preset);
    expect(s2.archive.background.key, 'jade');
  });

  test('清空全部保留管理员密码', () async {
    final AppState s = await _state();
    s.addMember(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期');
    s.changePassword(kDefaultAdminPassword, 'secret', 'secret');
    s.clearAll();
    expect(s.archive.memberList, isEmpty);
    expect(s.archive.adminPassword, 'secret');
  });

  test('持久化：改动后可被重新读取', () async {
    final MemoryBackend backend = MemoryBackend();
    final AppState s = AppState(repository: LocalRepository(backend: backend));
    await s.init();
    s.addMember(name: '持久甲', role: '外门弟子', mainRank: '炼气', subRank: '前期');
    await s.flush();

    final AppState reloaded = AppState(
      repository: LocalRepository(backend: backend),
    );
    await reloaded.init();
    expect(reloaded.archive.memberList.single.name, '持久甲');
  });
}
