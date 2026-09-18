/// 成绩导入：场次管理、文本/CSV/XLSX 导入、统计、分数段、个人追踪、两场对比、CSV 导出。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/file_utils.dart';
import '../../core/parsers.dart';
import '../../core/tabular.dart';
import '../../core/theme.dart';
import '../../data/xlsx.dart';
import '../../domain/analytics.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/admin_bar.dart';
import '../../widgets/badges.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/member_avatar.dart';
import '../../widgets/number_field.dart';
import '../../widgets/page_body.dart';
import '../../widgets/stat_chips.dart';
import 'exam_chart.dart';

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key});

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _thresholdController = TextEditingController();
  final TextEditingController _excellentController = TextEditingController();

  String? _trackMember;
  String _compareA = '';
  String _compareB = '';
  final TextEditingController _manualScoreController = TextEditingController();
  bool _thresholdsInitialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    _textController.dispose();
    _thresholdController.dispose();
    _excellentController.dispose();
    _manualScoreController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Archive archive = state.archive;
    final ExamData data = archive.examData;
    final bool unlocked = state.unlocked;
    final ExamSession? session = data.current;

    if (!_thresholdsInitialized) {
      _thresholdsInitialized = true;
      _thresholdController.text = formatNumber(data.threshold);
      _excellentController.text = formatNumber(data.thresholdExcellent);
    }

    if (_compareA.isEmpty && data.sessions.isNotEmpty) {
      _compareA = data.sessions.length >= 2
          ? data.sessions[data.sessions.length - 2].id
          : data.sessions.last.id;
    }
    if (_compareB.isEmpty && data.sessions.isNotEmpty) {
      _compareB = data.sessions.last.id;
    }

    return PageBody(
      children: <Widget>[
        PageHeader(
          title: '成绩导入',
          subtitle:
              '每次导入保存为一场新考试，历史完整保留；支持 CSV / TXT / XLSX 并自动匹配宗门名单，'
              '可查看个人历场趋势与任意两场对比。',
          actions: <Widget>[AdminStatusTile(compact: true)],
        ),
        _sessionCard(state, archive, data, unlocked),
        const SizedBox(height: 16),
        _thresholdCard(state, data, unlocked),
        const SizedBox(height: 16),
        _scoreTableCard(state, archive, session, unlocked),
        const SizedBox(height: 16),
        _statsCard(archive, session, data),
        const SizedBox(height: 16),
        _trackCard(archive, data, unlocked),
        const SizedBox(height: 16),
        _peakSummaryCard(archive, session),
        const SizedBox(height: 16),
        _compareCard(archive, data, unlocked),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 场次管理 + 导入
  // ------------------------------------------------------------------
  Widget _sessionCard(
    AppState state,
    Archive archive,
    ExamData data,
    bool unlocked,
  ) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('考试场次与导入', subtitle: '导入前请先新建或选择场次'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      data.sessions.any(
                        (ExamSession s) => s.id == data.currentSession,
                      )
                      ? data.currentSession
                      : null,
                  decoration: const InputDecoration(labelText: '当前场次'),
                  items: <DropdownMenuItem<String>>[
                    for (int i = 0; i < data.sessions.length; i++)
                      DropdownMenuItem<String>(
                        value: data.sessions[i].id,
                        child: Text(sessionLabel(data.sessions[i], i)),
                      ),
                  ],
                  onChanged: data.sessions.isEmpty
                      ? null
                      : (String? v) => state.switchExamSession(v ?? ''),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _nameController,
                  enabled: unlocked,
                  decoration: const InputDecoration(labelText: '考试名称'),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _timeController,
                  enabled: unlocked,
                  decoration: const InputDecoration(
                    labelText: '考试时间（留空自动）',
                    hintText: '2026-03-15 10:00',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: unlocked
                    ? () {
                        final String? err = state.newExamSession(
                          name: _nameController.text,
                          time: _timeController.text,
                        );
                        if (err != null) {
                          _toast(err);
                          return;
                        }
                        _nameController.clear();
                        _timeController.clear();
                        _toast('已新建场次');
                      }
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建场次'),
              ),
              OutlinedButton.icon(
                onPressed: unlocked && data.current != null
                    ? () async {
                        final ExamSession s = data.current!;
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: Text('删除本场「${s.name}」'),
                            content: Text('本场 ${s.records.length} 条成绩将被删除。'),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok ?? false) {
                          state.deleteExamSession(s.id);
                          _toast('场次已删除');
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除本场'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            enabled: unlocked,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '批量成绩文本',
              hintText:
                  '每行一条「姓名 成绩」，支持空格 / 逗号 / 冒号 / 制表符\n云逍遥 98\n林晚晴，87.5\n沈青霜：92',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: unlocked
                    ? () {
                        final String msg = state.importScoresFromText(
                          name: _nameController.text,
                          text: _textController.text,
                          time: _timeController.text,
                        );
                        if (!msg.startsWith('失败')) {
                          _textController.clear();
                          _nameController.clear();
                          _timeController.clear();
                        }
                        _showMessage('导入结果', msg);
                      }
                    : null,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('导入为考试'),
              ),
              OutlinedButton.icon(
                onPressed: unlocked ? () => _importFile(state) : null,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('导入文件（CSV/TXT/XLSX）'),
              ),
            ],
          ),
          const Divider(height: 30),
          const SectionTitle('手动补录成绩', subtitle: '选择成员并填写成绩，已存在则覆盖'),
          _manualScoreRow(state, archive, data, unlocked),
        ],
      ),
    );
  }

  Widget _manualScoreRow(
    AppState state,
    Archive archive,
    ExamData data,
    bool unlocked,
  ) {
    String? selected;
    return StatefulBuilder(
      builder:
          (BuildContext context, void Function(void Function()) setLocal) =>
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: '选择成员'),
                      items: archive.memberList
                          .map(
                            (Member m) => DropdownMenuItem<String>(
                              value: m.name,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                      onChanged: unlocked
                          ? (String? v) => setLocal(() => selected = v)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _manualScoreController,
                      enabled: unlocked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '成绩'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: unlocked && data.current != null
                        ? () {
                            if (selected == null) {
                              _toast('请选择成员');
                              return;
                            }
                            final double? score = double.tryParse(
                              _manualScoreController.text.trim(),
                            );
                            if (score == null) {
                              _toast('请输入有效成绩');
                              return;
                            }
                            state.addExamRecord(selected!, score);
                            _manualScoreController.clear();
                            setLocal(() => selected = null);
                            _toast('已记录成绩');
                          }
                        : null,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('添加成员成绩'),
                  ),
                  if (data.current == null)
                    const Text(
                      '请先新建或选择一场考试',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
    );
  }

  Future<void> _importFile(AppState state) async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['csv', 'txt', 'xlsx', 'xls'],
      dialogTitle: '选择成绩文件',
    );
    if (picked == null) return;

    List<List<String>> grid;
    try {
      if (picked.name.toLowerCase().endsWith('xlsx')) {
        grid = readXlsxGrid(picked.bytes);
      } else {
        grid = parseDelimited(utf8.decode(picked.bytes, allowMalformed: true));
      }
    } catch (e) {
      _toast('文件解析失败：$e');
      return;
    }
    if (grid.isEmpty) {
      _toast('文件中没有可解析的数据');
      return;
    }
    final ({int nameCol, int scoreCol}) guess = guessColumns(grid);
    await _showColumnPicker(
      state,
      picked.name,
      grid,
      guess.nameCol,
      guess.scoreCol,
    );
  }

  Future<void> _showColumnPicker(
    AppState state,
    String fileName,
    List<List<String>> grid,
    int nameCol,
    int scoreCol,
  ) async {
    int name = nameCol;
    int score = scoreCol;
    final TextEditingController nameCtl = TextEditingController(
      text: _nameController.text,
    );
    final TextEditingController timeCtl = TextEditingController(
      text: _timeController.text,
    );

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) {
          final int cols = grid.first.length;
          return AlertDialog(
            title: const Text('选择姓名列 / 成绩列'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '$fileName · 共 ${grid.length} 行，前 3 行预览：\n'
                    '${grid.take(3).map((List<String> r) => r.join(' | ')).join('\n')}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: name.clamp(0, cols - 1),
                          decoration: const InputDecoration(labelText: '姓名列'),
                          items: List<DropdownMenuItem<int>>.generate(
                            cols,
                            (int i) => DropdownMenuItem<int>(
                              value: i,
                              child: Text('第 ${i + 1} 列：${grid.first[i]}'),
                            ),
                          ),
                          onChanged: (int? v) =>
                              setLocal(() => name = v ?? name),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: score.clamp(0, cols - 1),
                          decoration: const InputDecoration(labelText: '成绩列'),
                          items: List<DropdownMenuItem<int>>.generate(
                            cols,
                            (int i) => DropdownMenuItem<int>(
                              value: i,
                              child: Text('第 ${i + 1} 列：${grid.first[i]}'),
                            ),
                          ),
                          onChanged: (int? v) =>
                              setLocal(() => score = v ?? score),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtl,
                    decoration: const InputDecoration(labelText: '考试名称'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: timeCtl,
                    decoration: const InputDecoration(labelText: '考试时间（留空自动）'),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final List<ExamRecord> records = gridToRecords(
                    grid,
                    nameCol: name,
                    scoreCol: score,
                    skipFirstRow: looksLikeHeader(grid.first),
                  );
                  Navigator.pop(ctx);
                  if (records.isEmpty) {
                    _toast('未解析到有效成绩行');
                    return;
                  }
                  final String msg = state.createSessionFromRecords(
                    name: nameCtl.text,
                    records: records,
                    time: timeCtl.text,
                  );
                  if (msg.startsWith('失败')) {
                    _showMessage('导入失败', msg);
                    return;
                  }
                  _nameController.clear();
                  _timeController.clear();
                  _showMessage('导入结果', msg);
                },
                child: const Text('确定导入'),
              ),
            ],
          );
        },
      ),
    );
    nameCtl.dispose();
    timeCtl.dispose();
  }

  Future<void> _showMessage(String title, String content) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Text(content, style: const TextStyle(height: 1.7)),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 分数线
  // ------------------------------------------------------------------
  Widget _thresholdCard(AppState state, ExamData data, bool unlocked) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('分数线', subtitle: '≥优秀 = 优秀，≥达标 = 达标，其余不达标'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _thresholdController,
                  enabled: unlocked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '达标线'),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _excellentController,
                  enabled: unlocked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '优秀线'),
                ),
              ),
              FilledButton(
                onPressed: unlocked
                    ? () {
                        final double t =
                            double.tryParse(_thresholdController.text.trim()) ??
                            data.threshold;
                        final double e =
                            double.tryParse(_excellentController.text.trim()) ??
                            data.thresholdExcellent;
                        state.saveThreshold(t, e);
                        _toast('分数线已保存');
                      }
                    : null,
                child: const Text('保存分数线'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 本场成绩表
  // ------------------------------------------------------------------
  Widget _scoreTableCard(
    AppState state,
    Archive archive,
    ExamSession? session,
    bool unlocked,
  ) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            '本场成绩${session == null ? '' : ' · ${session.name}'}',
            subtitle: session == null
                ? null
                : '${session.records.length} 条记录 · ${session.time}',
            trailing: OutlinedButton.icon(
              onPressed: session == null || session.records.isEmpty
                  ? null
                  : () => _exportCsv(state, archive, session),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('导出本场 CSV'),
            ),
          ),
          if (session == null || session.records.isEmpty)
            const EmptyHint('本场暂无成绩：导入一场考试，或在下方手动添加成员成绩')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1000,
                child: Table(
                  columnWidths: const <int, TableColumnWidth>{
                    0: FixedColumnWidth(56),
                    1: FixedColumnWidth(64),
                    2: FixedColumnWidth(140),
                    3: FixedColumnWidth(260),
                    4: FixedColumnWidth(180),
                    5: FixedColumnWidth(110),
                    6: FixedColumnWidth(90),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: <TableRow>[
                    const TableRow(
                      children: <Widget>[
                        _Th('位次'),
                        _Th('头像'),
                        _Th('姓名'),
                        _Th('宗门职务'),
                        _Th('修为境界'),
                        _Th('成绩'),
                        _Th('操作'),
                      ],
                    ),
                    for (int i = 0; i < session.sortedRecords.length; i++)
                      _scoreRow(
                        state,
                        archive,
                        session,
                        session.sortedRecords[i],
                        i,
                        unlocked,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  TableRow _scoreRow(
    AppState state,
    Archive archive,
    ExamSession session,
    ExamRecord rec,
    int i,
    bool unlocked,
  ) {
    final Member? m = archive.memberByName(rec.name);
    final Member view = m ?? Member(name: rec.name, role: '凡人', mainRank: '凡体');

    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? const Color(0x14000000) : null,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: RankNumber(i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MemberAvatar(member: view, onTap: null),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MedalName(rec.name, i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: m == null
              ? const Text(
                  '已离宗',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    RoleBadge(m.role, dense: true),
                    SubRoleChips(member: m),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: m == null
              ? const Text('—', style: TextStyle(color: AppColors.textFaint))
              : RealmBadge.of(m, dense: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: NumberField(
            value: rec.score.round(),
            width: 96,
            enabled: unlocked,
            onChanged: (int v) =>
                state.updateExamScore(session.id, rec.name, v.toDouble()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: unlocked
              ? TextButton(
                  onPressed: () => state.deleteExamRecord(session.id, rec.name),
                  child: const Text(
                    '删除',
                    style: TextStyle(fontSize: 12, color: AppColors.danger),
                  ),
                )
              : const Text('—', style: TextStyle(color: AppColors.textFaint)),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 统计 / 分数段 / 三档名单
  // ------------------------------------------------------------------
  Widget _statsCard(Archive archive, ExamSession? session, ExamData data) {
    final ExamStats stats = examStats(
      session,
      data.threshold,
      data.thresholdExcellent,
    );
    final List<ScoreBand> bands = examBands(session);
    final ExamZones zones = examZones(
      session,
      data.threshold,
      data.thresholdExcellent,
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('本场统计'),
          if (stats.isEmpty)
            const EmptyHint('暂无统计数据', icon: Icons.bar_chart_outlined)
          else ...<Widget>[
            StatChipWrap(
              chips: <StatChip>[
                StatChip('参考人数', '${stats.count}'),
                StatChip(
                  '平均分',
                  formatNumber((stats.average * 10).round() / 10),
                ),
                StatChip('最高分', formatNumber(stats.max)),
                StatChip('最低分', formatNumber(stats.min)),
                StatChip(
                  '优秀(≥${formatNumber(data.thresholdExcellent)})',
                  '${stats.excellentCount} 人',
                ),
                StatChip('达标', '${stats.passCount} 人'),
                StatChip('不达标', '${stats.failCount} 人'),
              ],
            ),
            const SizedBox(height: 18),
            const SectionTitle('分数段分布'),
            for (final ScoreBand b in bands)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 66,
                      child: Text(
                        b.label,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: b.percent / 100,
                          minHeight: 10,
                          backgroundColor: const Color(0x33101A2E),
                          color: AppColors.goldDeep,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${b.count} 人 · ${b.percent}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const SectionTitle('分数线名单'),
            _zoneRow(
              '优秀（≥${formatNumber(data.thresholdExcellent)}）',
              zones.excellent,
              AppColors.jade,
            ),
            _zoneRow(
              '达标（${formatNumber(data.threshold)} ~ ${formatNumber(data.thresholdExcellent)}）',
              zones.pass,
              AppColors.gold,
            ),
            _zoneRow(
              '不达标（<${formatNumber(data.threshold)}）',
              zones.fail,
              AppColors.danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _zoneRow(String label, List<String> names, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$label：${names.length} 人',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              names.isEmpty ? '—' : names.join('、'),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 个人追踪
  // ------------------------------------------------------------------
  Widget _trackCard(Archive archive, ExamData data, bool unlocked) {
    final List<TrackPoint> points = _trackMember == null
        ? <TrackPoint>[]
        : trackData(data, _trackMember!);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('个人成绩追踪', subtitle: '选择成员查看其历场成绩折线与排名变化'),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _trackMember,
              decoration: const InputDecoration(labelText: '选择成员'),
              items: archive.memberList
                  .map(
                    (Member m) => DropdownMenuItem<String>(
                      value: m.name,
                      child: Text(m.name),
                    ),
                  )
                  .toList(),
              onChanged: (String? v) => setState(() => _trackMember = v),
            ),
          ),
          const SizedBox(height: 14),
          ExamTrackChart(points: points),
          const SizedBox(height: 14),
          if (points.isEmpty)
            const EmptyHint('该成员暂无成绩记录')
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(3),
              },
              children: <TableRow>[
                const TableRow(
                  children: <Widget>[
                    _Th('场次'),
                    _Th('成绩'),
                    _Th('排名'),
                    _Th('考试时间'),
                  ],
                ),
                for (final TrackPoint p in points)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          p.sessionName,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          formatNumber(p.score),
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${p.rank} / ${p.total}',
                          style: const TextStyle(
                            color: AppColors.info,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          p.time.isEmpty ? '—' : p.time,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 山峰汇总
  // ------------------------------------------------------------------
  Widget _peakSummaryCard(Archive archive, ExamSession? session) {
    final PeakExamSummary summary = peakExamSummary(session, archive.peakList);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('山峰汇总（本场）', subtitle: '按峰内成员平均分排序'),
          if (summary.rows.isEmpty)
            const EmptyHint('尚未创建山峰', icon: Icons.landscape_outlined)
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
              },
              children: <TableRow>[
                const TableRow(
                  children: <Widget>[
                    _Th('山峰'),
                    _Th('参考人数'),
                    _Th('平均分'),
                    _Th('最高分'),
                  ],
                ),
                for (final PeakExamRow r in summary.rows)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          r.peak,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${r.count}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          r.average == null
                              ? '—'
                              : formatNumber((r.average! * 10).round() / 10),
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          r.max == null ? '—' : formatNumber(r.max!),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                TableRow(
                  decoration: const BoxDecoration(color: Color(0x1FF7E2A8)),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        summary.total.peak,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        '${summary.total.count}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        summary.total.average == null
                            ? '—'
                            : formatNumber(
                                (summary.total.average! * 10).round() / 10,
                              ),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        summary.total.max == null
                            ? '—'
                            : formatNumber(summary.total.max!),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 两场对比
  // ------------------------------------------------------------------
  Widget _compareCard(Archive archive, ExamData data, bool unlocked) {
    final ExamSession? sa = data.sessionById(_compareA);
    final ExamSession? sb = data.sessionById(_compareB);
    final List<CompareRow> rows = (sa != null && sb != null)
        ? compareSessions(sa, sb)
        : <CompareRow>[];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('成绩对比', subtitle: '选择任意两场，查看分数差值与排名变化'),
          if (data.sessions.length < 2)
            const EmptyHint('至少需要两场考试才能对比')
          else ...<Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        data.sessions.any((ExamSession s) => s.id == _compareA)
                        ? _compareA
                        : null,
                    decoration: const InputDecoration(labelText: '场次 A'),
                    items: <DropdownMenuItem<String>>[
                      for (int i = 0; i < data.sessions.length; i++)
                        DropdownMenuItem<String>(
                          value: data.sessions[i].id,
                          child: Text(sessionLabel(data.sessions[i], i)),
                        ),
                    ],
                    onChanged: (String? v) =>
                        setState(() => _compareA = v ?? _compareA),
                  ),
                ),
                const Text('对比', style: TextStyle(color: AppColors.textMuted)),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        data.sessions.any((ExamSession s) => s.id == _compareB)
                        ? _compareB
                        : null,
                    decoration: const InputDecoration(labelText: '场次 B'),
                    items: <DropdownMenuItem<String>>[
                      for (int i = 0; i < data.sessions.length; i++)
                        DropdownMenuItem<String>(
                          value: data.sessions[i].id,
                          child: Text(sessionLabel(data.sessions[i], i)),
                        ),
                    ],
                    onChanged: (String? v) =>
                        setState(() => _compareB = v ?? _compareB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              const EmptyHint('请选择两场成绩进行对比')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1040,
                  child: Table(
                    columnWidths: const <int, TableColumnWidth>{
                      0: FixedColumnWidth(50),
                      1: FixedColumnWidth(60),
                      2: FixedColumnWidth(130),
                      3: FixedColumnWidth(100),
                      4: FixedColumnWidth(100),
                      5: FixedColumnWidth(120),
                      6: FixedColumnWidth(110),
                      7: FixedColumnWidth(90),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: <TableRow>[
                      TableRow(
                        children: <Widget>[
                          const _Th('位次'),
                          const _Th('头像'),
                          const _Th('姓名'),
                          _Th(sa?.name ?? '场次A'),
                          _Th(sb?.name ?? '场次B'),
                          const _Th('差值'),
                          const _Th('排名变化'),
                          const _Th('状态'),
                        ],
                      ),
                      for (int i = 0; i < rows.length; i++)
                        _compareRow(archive, rows[i], i),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  TableRow _compareRow(Archive archive, CompareRow r, int i) {
    final Member? m = archive.memberByName(r.name);
    final Member view = m ?? Member(name: r.name, role: '凡人', mainRank: '凡体');
    final double? diff = r.diff;
    final int? change = r.rankChange;

    Widget diffWidget;
    if (r.status == CompareStatus.absent) {
      diffWidget = const Text(
        '—',
        style: TextStyle(color: AppColors.textFaint),
      );
    } else if (r.status == CompareStatus.added) {
      diffWidget = const Text(
        '新增',
        style: TextStyle(color: AppColors.jade, fontSize: 12),
      );
    } else {
      final Color color = diff == null
          ? AppColors.textFaint
          : (diff > 0
                ? AppColors.jade
                : (diff < 0 ? AppColors.danger : AppColors.textMuted));
      final String arrow = diff == null
          ? ''
          : (diff > 0 ? ' ▲' : (diff < 0 ? ' ▼' : ' —'));
      diffWidget = Text(
        '${diff == null ? '—' : (diff > 0 ? '+' : '') + formatNumber(diff)}$arrow',
        style: TextStyle(color: color, fontSize: 12),
      );
    }

    Widget rankWidget;
    if (r.status != CompareStatus.normal || change == null) {
      rankWidget = Text(
        r.status == CompareStatus.added ? '新入榜' : '—',
        style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
      );
    } else {
      final Color color = change > 0
          ? AppColors.jade
          : (change < 0 ? AppColors.danger : AppColors.textMuted);
      rankWidget = Text(
        change > 0 ? '↑$change' : (change < 0 ? '↓${change.abs()}' : '持平'),
        style: TextStyle(color: color, fontSize: 12),
      );
    }

    final Widget statusWidget = switch (r.status) {
      CompareStatus.absent => const Text(
        '缺考',
        style: TextStyle(color: AppColors.danger, fontSize: 12),
      ),
      CompareStatus.added => const Text(
        '新增',
        style: TextStyle(color: AppColors.jade, fontSize: 12),
      ),
      CompareStatus.normal => const Text(
        '—',
        style: TextStyle(color: AppColors.textFaint),
      ),
    };

    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? const Color(0x14000000) : null,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: RankNumber(i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MemberAvatar(member: view, size: 36),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MedalName(r.name, i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            r.scoreA == null ? '—' : formatNumber(r.scoreA!),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            r.scoreB == null ? '—' : formatNumber(r.scoreB!),
            style: const TextStyle(color: AppColors.gold, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: diffWidget,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: rankWidget,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: statusWidget,
        ),
      ],
    );
  }

  Future<void> _exportCsv(
    AppState state,
    Archive archive,
    ExamSession session,
  ) async {
    final StringBuffer csv = StringBuffer('\ufeff场次,姓名,宗门职务,修为境界,成绩,排名,等级\n');
    final List<ExamRecord> sorted = session.sortedRecords;
    for (int i = 0; i < sorted.length; i++) {
      final ExamRecord r = sorted[i];
      final Member? m = archive.memberByName(r.name);
      final String realm = m == null
          ? ''
          : (m.isMortal ? '凡体' : '${m.mainRank}境${m.subRank}');
      final String level = r.score >= state.archive.examData.thresholdExcellent
          ? '优秀'
          : (r.score >= state.archive.examData.threshold ? '达标' : '不达标');
      final List<String> cells = <String>[
        session.name,
        r.name,
        m?.role ?? '',
        realm,
        formatNumber(r.score),
        '${i + 1}',
        level,
      ];
      csv.write(
        '${cells.map((String c) => '"${c.replaceAll('"', '""')}"').join(',')}\n',
      );
    }
    final String? path = await saveTextFile(
      fileName: '落云宗-成绩-${session.name}.csv',
      content: csv.toString(),
    );
    if (path != null) _toast('已导出：$path');
  }
}

class _Th extends StatelessWidget {
  const _Th(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.goldDeep,
          fontSize: 12,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
