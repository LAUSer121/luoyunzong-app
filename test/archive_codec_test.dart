import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/domain/models.dart';

void main() {
  test('纯 JSON 存档可解析', () {
    final Archive archive = Archive(motto: '测试宗旨');
    final Archive? parsed = ArchiveCodec.decode(
      ArchiveCodec.encodeJson(archive),
    );
    expect(parsed, isNotNull);
    expect(parsed!.motto, '测试宗旨');
    expect(parsed.adminPassword, '123456');
  });

  test('旧版 JS 存档（window.__LUOYUN_SAVE__）可解析', () {
    final String legacy =
        '/* 落云宗自动存档 */\n'
        'window.__LUOYUN_SAVE__ = {"archiveVersion":4,"adminPassword":"abc123",'
        '"memberList":[{"name":"云逍遥","role":"宗主","mainRank":"炼虚","subRank":"大圆满"}],'
        '"motto":"旧档宗旨"};\n';
    final Archive? parsed = ArchiveCodec.decode(legacy);
    expect(parsed, isNotNull);
    expect(parsed!.adminPassword, 'abc123');
    expect(parsed.memberList.single.name, '云逍遥');
    expect(parsed.motto, '旧档宗旨');
  });

  test('导出的 JS 存档可被再次解析（往返一致）', () {
    final Archive archive = Archive(
      memberList: <Member>[
        Member(name: '甲', role: '天骄', mainRank: '金丹', subRank: '后期'),
      ],
      peakList: <Peak>[
        Peak(
          name: '落云峰',
          leader: '甲',
          members: <PeakMember>[PeakMember(name: '甲', contribution: 5)],
        ),
      ],
    );
    final Archive? parsed = ArchiveCodec.decode(ArchiveCodec.encodeJs(archive));
    expect(parsed, isNotNull);
    expect(parsed!.memberList.single.role, '天骄');
    expect(parsed.peakList.single.total, 5);
  });

  test('坏文本返回 null', () {
    expect(ArchiveCodec.decode('这不是存档'), isNull);
    expect(ArchiveCodec.decode(''), isNull);
  });

  test('旧结构 categories 迁移为扁平 sessions', () {
    final Map<String, Object?> raw = <String, Object?>{
      'threshold': 70,
      'thresholdExcellent': 90,
      'categories': <Object?>[
        <String, Object?>{
          'name': '文化课',
          'sessions': <Object?>[
            <String, Object?>{
              'id': 'old1',
              'name': '第一次月考',
              'time': '2025-09-01 09:00',
              'records': <Object?>[
                <String, Object?>{'name': '甲', 'score': 88},
              ],
            },
          ],
        },
        <String, Object?>{
          'name': '历史记录',
          'records': <Object?>[
            <String, Object?>{'name': '乙', 'score': 66},
          ],
        },
      ],
    };
    final ExamData data = migrateExamData(raw);
    expect(data.threshold, 70);
    expect(data.thresholdExcellent, 90);
    expect(data.sessions.length, 2);
    expect(data.sessions.first.name, '第一次月考');
    expect(data.sessions.last.name, '历史记录');
    expect(data.currentSession, data.sessions.last.id);
  });

  test('存档字段名与旧版保持一致', () {
    final Archive archive = Archive(notice: '公告', updateText: '更新');
    final Map<String, Object?> json =
        jsonDecode(ArchiveCodec.encodeJson(archive)) as Map<String, Object?>;
    expect(json.containsKey('task_tian'), isTrue);
    expect(json.containsKey('task_di'), isTrue);
    expect(json.containsKey('task_xuan'), isTrue);
    expect(json.containsKey('task_huang'), isTrue);
    expect(json['update'], '更新');
    expect(json['notice'], '公告');
    expect(json['motto'], isNotNull);
    expect(json['examData'], isA<Map<String, Object?>>());
    expect((json['bg']! as Map<String, Object?>)['type'], 'default');
  });

  test('成员职务变化后名单按权重排序', () {
    final Archive archive = Archive(
      memberList: <Member>[
        Member(name: '甲', role: '外门弟子'),
        Member(name: '乙', role: '宗主'),
        Member(name: '丙', role: '长老'),
      ],
    );
    archive.sortMembers();
    expect(archive.memberList.map((Member m) => m.name), <String>[
      '乙',
      '丙',
      '甲',
    ]);
  });

  test('凡人修为分为 0，境界文本为凡体', () {
    final Member mortal = Member(
      name: '凡人甲',
      role: '凡人',
      mainRank: '凡体',
      subRank: '',
    );
    expect(mortal.realmScore, 0);
    expect(mortal.realmText, '凡体');
    final Member cultivator = Member(
      name: '乙',
      role: '天骄',
      mainRank: '金丹',
      subRank: '后期',
    );
    expect(cultivator.realmScore, 33);
  });
}
