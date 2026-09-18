import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/core/parsers.dart';
import 'package:luoyunzong/domain/models.dart';

void main() {
  group('parseMemberLines', () {
    test('缺省职务与境界，支持多种分隔符', () {
      final MemberParseResult r = parseMemberLines(
        '云逍遥 宗主 炼虚大圆满\n'
        '林晚晴，长老，元婴后期\n'
        '张三：凡人\n'
        '李四 外门弟子 筑基中期\n'
        '王五\t内门弟子\t金丹前期',
        <String>{},
      );
      expect(r.added.length, 5);
      final Member yun = r.added.firstWhere((Member m) => m.name == '云逍遥');
      expect(yun.role, '宗主');
      expect(yun.mainRank, '炼虚');
      expect(yun.subRank, '大圆满');
      final Member zhang = r.added.firstWhere((Member m) => m.name == '张三');
      expect(zhang.role, '凡人');
      expect(zhang.mainRank, '凡体');
      expect(zhang.subRank, '');
      final Member wang = r.added.firstWhere((Member m) => m.name == '王五');
      expect(wang.role, '内门弟子');
      expect(wang.mainRank, '金丹');
    });

    test('仅有姓名的行使用默认值', () {
      final MemberParseResult r = parseMemberLines('赵六', <String>{});
      expect(r.added.single.role, '外门弟子');
      expect(r.added.single.mainRank, '炼气');
      expect(r.added.single.subRank, '前期');
    });

    test('同名成员跳过并记录', () {
      final MemberParseResult r = parseMemberLines('云逍遥 宗主\n云逍遥 长老', <String>{
        '云逍遥',
      });
      expect(r.added, isEmpty);
      expect(r.duplicated, <String>['云逍遥', '云逍遥']);
    });
  });

  group('parseScoreLines', () {
    test('跳过表头与空行，识别多种分隔符', () {
      final ScoreParseResult r = parseScoreLines(
        '姓名,成绩\n'
        '云逍遥 98\n'
        '\n'
        '林晚晴，87.5\n'
        '沈青霜：92\n'
        '坏数据没有分数\n',
      );
      expect(r.valid.length, 3);
      expect(r.valid.first.name, '云逍遥');
      expect(r.valid.first.score, 98);
      expect(r.valid[1].score, 87.5);
      expect(r.invalid.length, 1);
    });

    test('负分与小数可解析', () {
      final ScoreParseResult r = parseScoreLines('某人 -3.5');
      expect(r.valid.single.score, -3.5);
    });
  });

  group('格式化', () {
    test('formatNumber 去掉多余小数位', () {
      expect(formatNumber(92.0), '92');
      expect(formatNumber(87.5), '87.5');
      expect(formatNumber(87.456), '87.46');
    });

    test('sessionLabel 带时间与人数', () {
      final ExamSession s = ExamSession(
        id: 's1',
        name: '三月演武',
        time: '2026-03-15 10:00',
        records: <ExamRecord>[
          ExamRecord(name: '甲', score: 90),
          ExamRecord(name: '乙', score: 80),
        ],
      );
      expect(sessionLabel(s, 0), '三月演武 03-15 10:00（2人）');
    });

    test('nowTimeStr 输出 16 位时间串', () {
      final String text = nowTimeStr(DateTime(2026, 3, 5, 9, 7));
      expect(text, '2026-03-05 09:07');
    });
  });
}
