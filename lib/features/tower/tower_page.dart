/// 通天塔榜单：录入通关记录、指定榜首。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/badges.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/member_avatar.dart';
import '../../widgets/page_body.dart';
import '../../widgets/portrait_dialog.dart';
import '../../widgets/stat_chips.dart';

class TowerPage extends StatefulWidget {
  const TowerPage({super.key});

  @override
  State<TowerPage> createState() => _TowerPageState();
}

class _TowerPageState extends State<TowerPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _countController = TextEditingController(
    text: '0',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
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
    final bool unlocked = state.unlocked;

    return PageBody(
      children: <Widget>[
        const PageHeader(
          title: '通天塔榜单',
          subtitle: '记录每位弟子的通关层数；榜首固定排第一，并自动获得「通天塔榜首」徽章。',
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionTitle('添加记录'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 220,
                    child: Autocomplete<String>(
                      optionsBuilder: (TextEditingValue v) {
                        if (v.text.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return archive.memberList
                            .map((Member m) => m.name)
                            .where((String n) => n.contains(v.text));
                      },
                      onSelected: (String v) => _nameController.text = v,
                      fieldViewBuilder:
                          (
                            BuildContext context,
                            TextEditingController controller,
                            FocusNode focusNode,
                            VoidCallback onSubmit,
                          ) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              enabled: unlocked,
                              decoration: const InputDecoration(
                                labelText: '弟子姓名（需已在名单中）',
                              ),
                              onChanged: (String v) => _nameController.text = v,
                            );
                          },
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _countController,
                      enabled: unlocked,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '已通关数量'),
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
                            final String? err = state.addTowerRecord(
                              name,
                              int.tryParse(_countController.text.trim()) ?? 0,
                            );
                            if (err != null) {
                              _toast(err);
                              return;
                            }
                            _nameController.clear();
                            _countController.text = '0';
                            _toast('已添加 $name 的通关记录');
                          }
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加记录'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (archive.towerList.isEmpty)
          const GlassCard(
            child: EmptyHint('暂无通天塔记录，请在上方录入', icon: Icons.stairs_outlined),
          )
        else
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1000,
                child: Table(
                  columnWidths: const <int, TableColumnWidth>{
                    0: FixedColumnWidth(56),
                    1: FixedColumnWidth(64),
                    2: FixedColumnWidth(140),
                    3: FixedColumnWidth(280),
                    4: FixedColumnWidth(190),
                    5: FixedColumnWidth(110),
                    6: FixedColumnWidth(160),
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
                        _Th('通关数'),
                        _Th('操作'),
                      ],
                    ),
                    for (int i = 0; i < archive.towerList.length; i++)
                      _row(state, archive, archive.towerList[i], i, unlocked),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  TableRow _row(
    AppState state,
    Archive archive,
    TowerRecord t,
    int i,
    bool unlocked,
  ) {
    final Member? m = archive.memberByName(t.name);
    final Member view =
        m ??
        Member(
          name: t.name,
          role: t.role,
          mainRank: t.mainRank,
          subRank: t.subRank,
        );
    return TableRow(
      decoration: BoxDecoration(
        color: t.isChampion
            ? const Color(0x22FFD766)
            : (i.isEven ? const Color(0x14000000) : null),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: RankNumber(i),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MemberAvatar(
            member: view,
            onTap: () => showPortraitDialog(context, t.name),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              MedalName(t.name, i),
              if (t.isChampion)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.military_tech,
                    size: 16,
                    color: Color(0xFFFFD766),
                  ),
                ),
            ],
          ),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: m == null
              ? RealmBadge(
                  mainRank: t.mainRank,
                  subRank: t.subRank,
                  dense: true,
                )
              : RealmBadge.of(m, dense: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '${t.passCount}',
            style: const TextStyle(color: AppColors.gold, fontSize: 15),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: unlocked
              ? Wrap(
                  spacing: 6,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () => _editCount(state, t),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('修改', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      onPressed: () => t.isChampion
                          ? state.unsetTowerChampion(t.name)
                          : state.setTowerChampion(t.name),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        t.isChampion ? '取消榜首' : '设为榜首',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: Text('删除 ${t.name} 的记录'),
                            content: const Text('确定删除该条通天塔记录？'),
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
                          state.deleteTowerRecord(t.name);
                          _toast('已删除 ${t.name} 的记录');
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

  Future<void> _editCount(AppState state, TowerRecord t) async {
    final TextEditingController controller = TextEditingController(
      text: '${t.passCount}',
    );
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('修改 ${t.name} 的通关数'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '已通关数量'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              state.updateTowerRecord(
                t.name,
                int.tryParse(controller.text.trim()) ?? 0,
              );
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
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
