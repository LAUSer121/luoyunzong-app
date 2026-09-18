/// 宗门公告 与 更新内容：两个长文本页。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/page_body.dart';

class BulletinPage extends StatefulWidget {
  const BulletinPage({super.key});

  @override
  State<BulletinPage> createState() => _BulletinPageState();
}

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _BulletinPageState extends State<BulletinPage> {
  final TextEditingController _controller = TextEditingController();
  Archive? _synced;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    if (!identical(_synced, state.archive)) {
      _synced = state.archive;
      if (_controller.text != state.archive.notice) {
        _controller.text = state.archive.notice;
      }
    }

    return PageBody(
      maxWidth: 980,
      children: <Widget>[
        PageHeader(
          title: '宗门公告',
          subtitle: state.unlocked
              ? '发布宗门通知、大典、奖惩、宗门要事（自动保存）'
              : '当前为只读模式，解锁后可编辑',
        ),
        GlassCard(
          ornament: true,
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _controller,
            enabled: state.unlocked,
            maxLines: 18,
            minLines: 12,
            onChanged: state.setNotice,
            style: const TextStyle(color: AppColors.text, height: 1.9),
            decoration: const InputDecoration(
              hintText: '撰写宗门公告…\n\n例：\n一、三月初五于落云峰举行入宗大典；\n二、本月宗门任务奖励翻倍。',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdatesPageState extends State<UpdatesPage> {
  final TextEditingController _controller = TextEditingController();
  Archive? _synced;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    if (!identical(_synced, state.archive)) {
      _synced = state.archive;
      if (_controller.text != state.archive.updateText) {
        _controller.text = state.archive.updateText;
      }
    }

    return PageBody(
      maxWidth: 980,
      children: <Widget>[
        PageHeader(
          title: '更新内容',
          subtitle: state.unlocked ? '记录剧情迭代设定、版本变更（自动保存）' : '当前为只读模式，解锁后可编辑',
        ),
        GlassCard(
          ornament: true,
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _controller,
            enabled: state.unlocked,
            maxLines: 18,
            minLines: 12,
            onChanged: state.setUpdateText,
            style: const TextStyle(color: AppColors.text, height: 1.9),
            decoration: const InputDecoration(
              hintText: '记录更新内容…\n\n例：\n【v1.2】新增山峰贡献点排行；\n【v1.1】成绩导入支持 XLSX。',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}
