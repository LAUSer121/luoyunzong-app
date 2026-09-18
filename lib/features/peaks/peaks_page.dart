/// 山峰：创建、招收、贡献点、改任峰主、解散。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/image_utils.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/badges.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/member_avatar.dart';
import '../../widgets/number_field.dart';
import '../../widgets/page_body.dart';
import '../../widgets/portrait_dialog.dart';
import '../../widgets/stat_chips.dart';

class PeaksPage extends StatefulWidget {
  const PeaksPage({super.key});

  @override
  State<PeaksPage> createState() => _PeaksPageState();
}

class _PeaksPageState extends State<PeaksPage> {
  final TextEditingController _nameController = TextEditingController();
  String? _leader;
  String? _avatar;

  @override
  void dispose() {
    _nameController.dispose();
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
    final List<Member> free = state.freeForPeak();

    return PageBody(
      children: <Widget>[
        const PageHeader(
          title: '山峰',
          subtitle:
              '创建山峰并招收弟子：每峰最多 $kPeakCapacity 人（含峰主），每人只能归属一座山峰；'
              '山峰总贡献 = 成员贡献点之和。',
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionTitle('创建山峰', subtitle: '峰主自动成为该峰第一位成员'),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  PeakAvatar(avatar: _avatar),
                  OutlinedButton(
                    onPressed: unlocked ? _pickAvatar : null,
                    child: const Text('峰头像'),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: _nameController,
                      enabled: unlocked,
                      decoration: const InputDecoration(labelText: '山峰名称'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      initialValue: _leader,
                      decoration: const InputDecoration(labelText: '峰主（未入峰成员）'),
                      items: free
                          .map(
                            (Member m) => DropdownMenuItem<String>(
                              value: m.name,
                              child: Text('${m.name}（${m.role}）'),
                            ),
                          )
                          .toList(),
                      onChanged: unlocked
                          ? (String? v) => setState(() => _leader = v)
                          : null,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: unlocked
                        ? () {
                            final String name = _nameController.text.trim();
                            if (_leader == null) {
                              _toast('请选择峰主');
                              return;
                            }
                            final String? err = state.createPeak(
                              name: name,
                              leader: _leader!,
                              avatar: _avatar,
                            );
                            if (err != null) {
                              _toast(err);
                              return;
                            }
                            _nameController.clear();
                            setState(() {
                              _leader = null;
                              _avatar = null;
                            });
                            _toast('山峰「$name」创建成功');
                          }
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('创建山峰'),
                  ),
                ],
              ),
              if (free.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    '暂无可用成员：所有弟子均已入峰，或名单为空（凡人不可为峰主）。',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (archive.peakList.isEmpty)
          const GlassCard(
            child: EmptyHint('尚无山峰，请在上方创建', icon: Icons.landscape_outlined),
          )
        else
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final bool wide = c.maxWidth >= 1000;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: archive.peakList.map((Peak p) {
                  final double w = wide ? (c.maxWidth - 16) / 2 : c.maxWidth;
                  return SizedBox(
                    width: w,
                    child: _peakCard(state, archive, p, unlocked),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Future<void> _pickAvatar() async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      dialogTitle: '选择峰头像',
    );
    if (picked == null) return;
    final String? data = compressImageToDataUrl(picked.bytes);
    if (data == null) {
      _toast('图片读取失败');
      return;
    }
    setState(() => _avatar = data);
  }

  Widget _peakCard(AppState state, Archive archive, Peak p, bool unlocked) {
    final List<Member> free = state.freeForPeak();
    final bool full = p.isFull;

    return GlassCard(
      ornament: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PeakAvatar(avatar: p.avatar),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '峰主：${p.leader} · 成员 ${p.members.length} / $kPeakCapacity',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Text(
                    '总贡献',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 11),
                  ),
                  Text(
                    '${p.total}',
                    style: const TextStyle(color: AppColors.gold, fontSize: 20),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (unlocked)
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: null,
                    decoration: const InputDecoration(
                      labelText: '招收弟子（未入峰）',
                      isDense: true,
                    ),
                    items: free
                        .map(
                          (Member m) => DropdownMenuItem<String>(
                            value: m.name,
                            child: Text('${m.name}（${m.role}）'),
                          ),
                        )
                        .toList(),
                    onChanged: (String? v) {
                      if (v == null) return;
                      final String? err = state.addPeakMember(p.name, v);
                      if (err != null) {
                        _toast(err);
                        return;
                      }
                      _toast('已招收 $v 入峰');
                    },
                  ),
                ),
              ],
            ),
          if (unlocked && full)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '该峰已达 $kPeakCapacity 人上限',
                style: TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(2.6),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(2.0),
              3: FlexColumnWidth(1.6),
              4: FlexColumnWidth(2.2),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              const TableRow(
                children: <Widget>[
                  _Th('成员'),
                  _Th('峰内职务'),
                  _Th('境界'),
                  _Th('贡献点'),
                  _Th('操作'),
                ],
              ),
              for (final PeakMember pm in p.members)
                _memberRow(state, archive, p, pm, unlocked),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '贡献点为手动维护，随存档导出导入。',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ),
              if (unlocked)
                TextButton.icon(
                  onPressed: () async {
                    final bool? ok = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext ctx) => AlertDialog(
                        title: Text('解散山峰「${p.name}」'),
                        content: const Text('成员将恢复为自由身，贡献点记录一并删除。确定继续？'),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('解散'),
                          ),
                        ],
                      ),
                    );
                    if (ok ?? false) {
                      state.deletePeak(p.name);
                      _toast('山峰已解散');
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('删除山峰', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _memberRow(
    AppState state,
    Archive archive,
    Peak p,
    PeakMember pm,
    bool unlocked,
  ) {
    final Member? info = archive.memberByName(pm.name);
    final bool isLeader = p.leader == pm.name;
    final Member view =
        info ??
        Member(name: pm.name, role: '外门弟子', mainRank: '炼气', subRank: '前期');

    return TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              MemberAvatar(
                member: view,
                size: 36,
                onTap: () => showPortraitDialog(context, pm.name),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(pm.name, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: isLeader
              ? const RoleBadge('峰主', dense: true)
              : const Text(
                  '弟子',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: info == null
              ? const Text(
                  '已离宗',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                )
              : RealmBadge.of(info, dense: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: NumberField(
            value: pm.contribution,
            width: 80,
            enabled: unlocked,
            onChanged: (int v) =>
                state.updatePeakContribution(p.name, pm.name, v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: unlocked && !isLeader
              ? Wrap(
                  spacing: 4,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () => state.setPeakLeader(p.name, pm.name),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('任峰主', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton(
                      onPressed: () {
                        final String? err = state.removePeakMember(
                          p.name,
                          pm.name,
                        );
                        if (err != null) {
                          _toast(err);
                          return;
                        }
                        _toast('已移除 ${pm.name}');
                      },
                      child: const Text(
                        '移除',
                        style: TextStyle(fontSize: 11, color: AppColors.danger),
                      ),
                    ),
                  ],
                )
              : Text(
                  isLeader ? '峰主' : '—',
                  style: TextStyle(
                    fontSize: 11,
                    color: isLeader
                        ? const Color(0xFFFFD9A8)
                        : AppColors.textFaint,
                  ),
                ),
        ),
      ],
    );
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
