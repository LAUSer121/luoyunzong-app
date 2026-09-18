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
  bool _expandAll = true;

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
              onPressed: () => setState(() => _expandAll = !_expandAll),
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

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('task-${grade.key}-$_expandAll'),
          initiallyExpanded: _expandAll,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 14),
          leading: Container(
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
          title: Row(
            children: <Widget>[
              Text(
                grade.title,
                style: const TextStyle(color: AppColors.gold, fontSize: 15),
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                const Text(
                  '可接职务：',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      r,
                      style: TextStyle(color: accent, fontSize: 11),
                    ),
                  ),
                ),
                if (conditions.isEmpty)
                  const Text(
                    '未设置',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
              ],
            ),
          ),
          trailing: state.unlocked
              ? OutlinedButton(
                  onPressed: () => _editConditions(state, grade, conditions),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('设置可接职务', style: TextStyle(fontSize: 12)),
                )
              : null,
          children: <Widget>[
            TextField(
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
          ],
        ),
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
