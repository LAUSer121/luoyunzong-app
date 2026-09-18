/// 权限区：只读/可编辑状态提示 + 解锁 / 加锁 / 修改密码。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';

class AdminStatusTile extends StatelessWidget {
  const AdminStatusTile({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final bool unlocked = state.unlocked;
    final Color color = unlocked ? AppColors.jade : AppColors.danger;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            unlocked ? Icons.lock_open_rounded : Icons.lock_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            unlocked ? '可编辑模式' : '只读模式',
            style: TextStyle(color: color, fontSize: compact ? 12 : 13),
          ),
        ],
      ),
    );
  }
}

/// 解锁对话框：密码正确返回 true。
Future<bool> showUnlockDialog(BuildContext context) async {
  final AppState state = context.read<AppState>();
  final TextEditingController controller = TextEditingController();
  String? error;

  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, void Function(void Function()) setState) {
        return AlertDialog(
          title: const Text('解锁编辑'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  '输入管理员密码后可录入名单、修改任务与成绩、管理山峰等。',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '管理员密码',
                    errorText: error,
                    prefixIcon: const Icon(Icons.key_outlined, size: 18),
                  ),
                  onSubmitted: (_) {
                    if (state.unlock(controller.text)) {
                      Navigator.pop(ctx, true);
                    } else {
                      setState(() => error = '密码不正确');
                    }
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (state.unlock(controller.text)) {
                  Navigator.pop(ctx, true);
                } else {
                  setState(() => error = '密码不正确');
                }
              },
              child: const Text('解锁'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return ok ?? false;
}

/// 修改管理员密码对话框。
Future<void> showChangePasswordDialog(BuildContext context) async {
  final AppState state = context.read<AppState>();
  final TextEditingController oldPwd = TextEditingController();
  final TextEditingController newPwd = TextEditingController();
  final TextEditingController confirm = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, void Function(void Function()) setState) =>
          AlertDialog(
            title: const Text('修改管理员密码'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: oldPwd,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '旧密码'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newPwd,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '新密码（至少 4 位）'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: '确认新密码',
                      errorText: error,
                    ),
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
                  final String? err = state.changePassword(
                    oldPwd.text,
                    newPwd.text,
                    confirm.text,
                  );
                  if (err != null) {
                    setState(() => error = err);
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('管理员密码已更新')));
                },
                child: const Text('确定'),
              ),
            ],
          ),
    ),
  );
  oldPwd.dispose();
  newPwd.dispose();
  confirm.dispose();
}
