/// 宗门名单：录入、批量导入、统计、编辑、立绘与视频。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/image_utils.dart';
import '../../core/parsers.dart';
import '../../core/theme.dart';
import '../../domain/analytics.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/admin_bar.dart';
import '../../widgets/badges.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/member_avatar.dart';
import '../../widgets/page_body.dart';
import '../../widgets/portrait_dialog.dart';
import '../../widgets/stat_chips.dart';

class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _batchController = TextEditingController();
  String _role = '外门弟子';
  String _mainRank = '炼气';
  String _subRank = '前期';
  String? _avatar;
  int _tab = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      dialogTitle: '选择头像',
    );
    if (picked == null) return;
    final String? data = compressImageToDataUrl(picked.bytes);
    if (data == null) {
      _toast('图片读取失败');
      return;
    }
    setState(() => _avatar = data);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final bool unlocked = state.unlocked;
    final Archive archive = state.archive;

    return PageBody(
      children: <Widget>[
        PageHeader(
          title: '落云宗',
          subtitle: '宗门名单 · 职务与境界管理；点击头像查看立绘与动态视频。',
          actions: <Widget>[AdminStatusTile(compact: true)],
        ),
        _mottoCard(state, archive),
        const SizedBox(height: 16),
        GlassCard(
          ornament: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionTitle('职务构成', subtitle: '名单实时统计'),
              StatChipWrap(chips: roleStats(archive)),
              const SizedBox(height: 18),
              const SectionTitle('境界分布'),
              StatChipWrap(
                chips: realmStats(archive)
                    .map(
                      (StatChip c) =>
                          StatChip(c.label, c.value, highlight: false),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _entryCard(state, unlocked),
        const SizedBox(height: 16),
        _memberTable(state, archive, unlocked),
      ],
    );
  }

  Widget _mottoCard(AppState state, Archive archive) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: <Widget>[
          const Icon(Icons.auto_awesome, color: AppColors.goldDeep, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              archive.motto,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
          if (state.unlocked)
            TextButton.icon(
              onPressed: () => _editMotto(state, archive.motto),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('修改宗旨'),
            ),
        ],
      ),
    );
  }

  Future<void> _editMotto(AppState state, String current) async {
    final TextEditingController controller = TextEditingController(
      text: current,
    );
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('修改宗门宗旨'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            maxLength: 80,
            autofocus: true,
            decoration: const InputDecoration(hintText: '一句话概括宗门理念'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              state.setMotto(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _entryCard(AppState state, bool unlocked) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle('成员录入', subtitle: unlocked ? '手动录入或批量粘贴名单' : '解锁编辑后可录入'),
          // 独立一行展示切换按钮，避免窄屏时与标题挤压换行。
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: Text('手动录入'),
                  icon: Icon(Icons.person_add_alt, size: 16),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('批量导入'),
                  icon: Icon(Icons.playlist_add, size: 16),
                ),
              ],
              selected: <int>{_tab},
              onSelectionChanged: (Set<int> v) =>
                  setState(() => _tab = v.first),
            ),
          ),
          const SizedBox(height: 14),
          if (_tab == 0)
            _manualForm(state, unlocked)
          else
            _batchForm(state, unlocked),
          const Divider(height: 30),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: unlocked
                    ? () async {
                        await state.flush();
                        _toast('存档已保存（${state.storageLabel}）');
                      }
                    : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('立即保存存档'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await state.init();
                  _toast('已从存档重新载入');
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新读取存档'),
              ),
              OutlinedButton.icon(
                onPressed: unlocked
                    ? () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: const Text('清空全部数据'),
                            content: const Text(
                              '将删除名单、通天塔、山峰、成绩与背景设置，管理员密码保留。确定继续？',
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                        if (ok ?? false) {
                          state.clearAll();
                          _toast('已清空全部数据');
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空全部'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _manualForm(AppState state, bool unlocked) {
    final Uint8List? avatarBytes = _avatar == null
        ? null
        : dataUrlToBytes(_avatar!);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        GestureDetector(
          onTap: unlocked ? _pickAvatar : null,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.goldDeep.withValues(alpha: 0.5),
              ),
              color: const Color(0x33101A2E),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarBytes != null
                ? Image.memory(avatarBytes, fit: BoxFit.cover)
                : const Center(
                    child: Text(
                      '侠',
                      style: TextStyle(color: AppColors.goldDeep, fontSize: 28),
                    ),
                  ),
          ),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _nameController,
            enabled: unlocked,
            decoration: const InputDecoration(labelText: '姓名'),
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: '宗门职务'),
            items: kRoleOptions
                .map(
                  (String r) =>
                      DropdownMenuItem<String>(value: r, child: Text(r)),
                )
                .toList(),
            onChanged: unlocked
                ? (String? v) => setState(() => _role = v ?? _role)
                : null,
          ),
        ),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<String>(
            initialValue: _role == '凡人' ? kMortalRealm : _mainRank,
            decoration: const InputDecoration(labelText: '修为主阶'),
            items: _role == '凡人'
                ? const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: kMortalRealm,
                      child: Text('凡体'),
                    ),
                  ]
                : kMainRankOptions
                      .map(
                        (String r) => DropdownMenuItem<String>(
                          value: r,
                          child: Text('$r境'),
                        ),
                      )
                      .toList(),
            onChanged: unlocked && _role != '凡人'
                ? (String? v) => setState(() => _mainRank = v ?? _mainRank)
                : null,
          ),
        ),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<String>(
            initialValue: _role == '凡人' ? '—' : _subRank,
            decoration: const InputDecoration(labelText: '修为小阶'),
            items: _role == '凡人'
                ? const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: '—', child: Text('凡人不设境界')),
                  ]
                : kSubRankOptions
                      .map(
                        (String r) =>
                            DropdownMenuItem<String>(value: r, child: Text(r)),
                      )
                      .toList(),
            onChanged: unlocked && _role != '凡人'
                ? (String? v) => setState(() => _subRank = v ?? _subRank)
                : null,
          ),
        ),
        FilledButton.icon(
          onPressed: unlocked
              ? () {
                  final String name = _nameController.text.trim();
                  if (name.isEmpty) {
                    _toast('请输入弟子姓名');
                    return;
                  }
                  if (state.archive.memberByName(name) != null) {
                    _toast('已存在同名成员：$name');
                    return;
                  }
                  state.addMember(
                    name: name,
                    role: _role,
                    mainRank: _mainRank,
                    subRank: _subRank,
                    avatar: _avatar,
                  );
                  setState(() {
                    _nameController.clear();
                    _avatar = null;
                  });
                  _toast('已录入：$name');
                }
              : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('录入名单'),
        ),
      ],
    );
  }

  Widget _batchForm(AppState state, bool unlocked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '每行一条「姓名 职务 境界」，支持空格 / 逗号 / 冒号 / 制表符分隔；\n'
          '职务缺省为外门弟子，境界缺省为炼气前期；职务写「凡人」则境界自动为凡体；同名成员自动跳过。\n'
          '示例：云逍遥 宗主 炼虚大圆满　|　林晚晴，长老，元婴后期　|　张三：凡人',
          style: TextStyle(
            color: AppColors.textFaint,
            fontSize: 12,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _batchController,
          enabled: unlocked,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '云逍遥 宗主 炼虚大圆满\n林晚晴，长老，元婴后期\n张三：凡人\n李四 外门弟子 筑基中期',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: unlocked
              ? () {
                  final String text = _batchController.text;
                  if (text.trim().isEmpty) {
                    _toast('请先粘贴名单文本');
                    return;
                  }
                  final MemberParseResult result = state.importMembers(text);
                  _batchController.clear();
                  _showImportResult(result);
                }
              : null,
          icon: const Icon(Icons.playlist_add_check, size: 18),
          label: const Text('一键导入名单'),
        ),
      ],
    );
  }

  Future<void> _showImportResult(MemberParseResult r) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('导入结果'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('成功新增 ${r.added.length} 人'),
              if (r.duplicated.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '跳过同名 ${r.duplicated.length} 人：${r.duplicated.take(10).join('、')}'
                    '${r.duplicated.length > 10 ? '…' : ''}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (r.invalidLines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '无法识别 ${r.invalidLines.length} 行：${r.invalidLines.take(5).join('、')}',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
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

  Widget _memberTable(AppState state, Archive archive, bool unlocked) {
    if (archive.memberList.isEmpty) {
      return const GlassCard(
        child: EmptyHint('暂无成员，请在上方录入或批量导入名单', icon: Icons.groups_2_outlined),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: SectionTitle('成员名册', subtitle: '按职务权重排序，前三名金银铜高亮'),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 980),
              child: SizedBox(
                width: 980,
                child: Table(
                  columnWidths: const <int, TableColumnWidth>{
                    0: FixedColumnWidth(56),
                    1: FixedColumnWidth(64),
                    2: FixedColumnWidth(140),
                    3: FixedColumnWidth(280),
                    4: FixedColumnWidth(190),
                    5: FixedColumnWidth(90),
                    6: FixedColumnWidth(150),
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
                        _Th('贡献点'),
                        _Th('操作'),
                      ],
                    ),
                    for (int i = 0; i < archive.memberList.length; i++)
                      _memberRow(state, archive.memberList[i], i, unlocked),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _memberRow(AppState state, Member m, int i, bool unlocked) {
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? const Color(0x14000000) : null,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: RankNumber(i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MemberAvatar(
            member: m,
            onTap: () => showPortraitDialog(context, m.name),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: MedalName(m.name, i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              RoleBadge(m.role, dense: true),
              SubRoleChips(member: m),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: RealmBadge.of(m),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '${m.contribution}',
            style: const TextStyle(color: AppColors.jade, fontSize: 14),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: unlocked
              ? Wrap(
                  spacing: 6,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () => _editMember(state, m),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('修改', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: Text('删除 ${m.name}'),
                            content: const Text('将同时清理其通天塔记录与山峰归属，确定继续？'),
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
                          state.deleteMember(m.name);
                          _toast('已删除 ${m.name}');
                        }
                      },
                      child: const Text(
                        '删除',
                        style: TextStyle(fontSize: 12, color: AppColors.danger),
                      ),
                    ),
                  ],
                )
              : const Text('—', style: TextStyle(color: AppColors.textFaint)),
        ),
      ],
    );
  }

  Future<void> _editMember(AppState state, Member m) async {
    String role = m.role;
    String mainRank = m.mainRank == kMortalRealm ? '炼气' : m.mainRank;
    String subRank = m.subRank.isEmpty ? '前期' : m.subRank;
    final TextEditingController contribution = TextEditingController(
      text: '${m.contribution}',
    );
    final List<String> subRoles = List<String>.of(m.subRoles);

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) =>
            AlertDialog(
              title: Text('修改 ${m.name}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: '宗门职务'),
                        items: kRoleOptions
                            .map(
                              (String r) => DropdownMenuItem<String>(
                                value: r,
                                child: Text(r),
                              ),
                            )
                            .toList(),
                        onChanged: (String? v) =>
                            setLocal(() => role = v ?? role),
                      ),
                      const SizedBox(height: 12),
                      if (role == '凡人')
                        const Text(
                          '凡人不设境界',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: mainRank,
                                decoration: const InputDecoration(
                                  labelText: '修为主阶',
                                ),
                                items: kMainRankOptions
                                    .map(
                                      (String r) => DropdownMenuItem<String>(
                                        value: r,
                                        child: Text('$r境'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (String? v) =>
                                    setLocal(() => mainRank = v ?? mainRank),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: subRank,
                                decoration: const InputDecoration(
                                  labelText: '修为小阶',
                                ),
                                items: kSubRankOptions
                                    .map(
                                      (String r) => DropdownMenuItem<String>(
                                        value: r,
                                        child: Text(r),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (String? v) =>
                                    setLocal(() => subRank = v ?? subRank),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contribution,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '贡献点'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '兼任职务 / 荣誉职衔',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kRoleOptions
                            .where((String r) => r != role)
                            .map(
                              (String r) => FilterChip(
                                label: Text(
                                  r,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: subRoles.contains(r),
                                onSelected: (bool on) => setLocal(() {
                                  if (on) {
                                    if (!subRoles.contains(r)) subRoles.add(r);
                                  } else {
                                    subRoles.remove(r);
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    state.updateMember(
                      m.name,
                      role: role,
                      mainRank: role == '凡人' ? kMortalRealm : mainRank,
                      subRank: role == '凡人' ? '' : subRank,
                      contribution:
                          int.tryParse(contribution.text.trim()) ??
                          m.contribution,
                      subRoles: subRoles
                          .where((String r) => r != role)
                          .toList(),
                    );
                    Navigator.pop(ctx);
                    _toast('已保存 ${m.name} 的资料');
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
      ),
    );
    contribution.dispose();
  }
}

class _Th extends StatelessWidget {
  const _Th(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.goldDeep,
          fontSize: 13,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
