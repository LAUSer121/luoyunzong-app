/// 宗门任务：天 / 地 / 玄 / 黄 四档，可折叠，可多选可接职务、编辑任务详情。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/page_body.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final Map<TaskGrade, TextEditingController> _controllers =
      <TaskGrade, TextEditingController>{
        for (final TaskGrade g in TaskGrade.values) g: TextEditingController(),
      };
  Archive? _synced;

  /// 展开的档位（自己管，替代 ExpansionTile + PageStorageKey：
  /// 那套在「收起再展开」时会因为 key 变化重建，出现过整页空白）。
  late final Set<String> _expanded = <String>{
    for (final TaskGrade g in TaskGrade.values) g.key,
  };

  bool get _expandAll => _expanded.length == TaskGrade.values.length;

  void _toggle(TaskGrade grade) {
    setState(() {
      if (!_expanded.remove(grade.key)) _expanded.add(grade.key);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_expandAll) {
        _expanded.clear();
      } else {
        _expanded.addAll(TaskGrade.values.map((TaskGrade g) => g.key));
      }
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(Archive archive) {
    if (identical(_synced, archive)) return;
    _synced = archive;
    for (final TaskGrade g in TaskGrade.values) {
      final String text = archive.tasks[g.key] ?? '';
      if (_controllers[g]!.text != text) _controllers[g]!.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Archive archive = state.archive;
    _syncControllers(archive);

    return PageBody(
      maxWidth: 1080,
      children: <Widget>[
        PageHeader(
          title: '宗门任务',
          subtitle: '点击标题展开 / 收起任务详情；「可接职务」可手动多选接取范围。',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: _toggleAll,
              icon: Icon(
                _expandAll ? Icons.unfold_less : Icons.unfold_more,
                size: 16,
              ),
              label: Text(_expandAll ? '全部收起' : '全部展开'),
            ),
          ],
        ),
        for (final TaskGrade g in TaskGrade.values) ...<Widget>[
          _gradeCard(state, archive, g),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _gradeCard(AppState state, Archive archive, TaskGrade grade) {
    final List<String> conditions =
        archive.taskConditions[grade.key] ??
        kDefaultTaskConditions[grade.key] ??
        <String>[];
    final Color accent = _gradeColor(grade);
    final bool expanded = _expanded.contains(grade.key);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 标题行：整行可点，右侧按钮单独响应（不会误触折叠）。
          InkWell(
            onTap: () => _toggle(grade),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(color: accent.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      grade.emblem,
                      style: TextStyle(color: accent, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              grade.title,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                grade.description,
                                style: const TextStyle(
                                  color: AppColors.textFaint,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              const Text(
                                '可接职务：',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              ...conditions.map(
                                (String r) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              if (conditions.isEmpty)
                                const Text(
                                  '未设置',
                                  style: TextStyle(
                                    color: AppColors.textFaint,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.unlocked) ...<Widget>[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () =>
                          _editConditions(state, grade, conditions),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        '设置可接职务',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textFaint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          // 内容区：自己用 AnimatedSize 控制显隐（不依赖 ExpansionTile/PageStorage）。
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: _controllers[grade]!,
                      enabled: state.unlocked,
                      maxLines: 8,
                      minLines: 4,
                      onChanged: (String v) => state.setTaskText(grade, v),
                      decoration: InputDecoration(
                        hintText: '录入${grade.title}详情…（支持多行）',
                        alignLabelWithHint: true,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _editConditions(
    AppState state,
    TaskGrade grade,
    List<String> current,
  ) async {
    final List<String> selected = List<String>.of(current);
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) =>
            AlertDialog(
              title: Text('${grade.title} · 可接职务'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final String role in kRoleOptions)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(role),
                          title: Text(
                            role,
                            style: const TextStyle(fontSize: 13),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? on) => setLocal(() {
                            if (on ?? false) {
                              if (!selected.contains(role)) selected.add(role);
                            } else {
                              selected.remove(role);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => setLocal(
                    () => selected
                      ..clear()
                      ..addAll(kDefaultTaskConditions[grade.key] ?? <String>[]),
                  ),
                  child: const Text('恢复默认'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    state.setTaskConditions(grade, selected);
                    Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
      ),
    );
  }

  Color _gradeColor(TaskGrade g) => switch (g) {
    TaskGrade.tian => const Color(0xFFFFD766),
    TaskGrade.di => const Color(0xFFD4A0FF),
    TaskGrade.xuan => const Color(0xFF7DB8FF),
    TaskGrade.huang => const Color(0xFF9AE6C8),
  };
}
