/// 应用入口：主题、响应式外壳（桌面侧栏 / 手机底部导航 + 抽屉）、背景与 BGM 悬浮层。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'features/bgm/bgm_player.dart';
import 'features/bulletin/bulletin_page.dart';
import 'features/exams/exams_page.dart';
import 'features/peaks/peaks_page.dart';
import 'features/ranking/ranking_page.dart';
import 'features/roster/roster_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tasks/tasks_page.dart';
import 'features/tower/tower_page.dart';
import 'state/app_state.dart';
import 'widgets/admin_bar.dart';
import 'widgets/app_background.dart';

class LuoyunzongApp extends StatelessWidget {
  const LuoyunzongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '落云宗 · 宗门管理',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _bgmStarted = false;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination('宗门名单', Icons.groups_2_outlined, Icons.groups_2, RosterPage()),
    _Destination(
      '宗门排行榜',
      Icons.emoji_events_outlined,
      Icons.emoji_events,
      RankingPage(),
    ),
    _Destination(
      '宗门任务',
      Icons.assignment_outlined,
      Icons.assignment,
      TasksPage(),
    ),
    _Destination('通天塔榜单', Icons.stairs_outlined, Icons.stairs, TowerPage()),
    _Destination('山峰', Icons.landscape_outlined, Icons.landscape, PeaksPage()),
    _Destination(
      '成绩导入',
      Icons.assessment_outlined,
      Icons.assessment,
      ExamsPage(),
    ),
    _Destination(
      '宗门公告',
      Icons.campaign_outlined,
      Icons.campaign,
      BulletinPage(),
    ),
    _Destination(
      '更新内容',
      Icons.history_edu_outlined,
      Icons.history_edu,
      UpdatesPage(),
    ),
    _Destination('设置', Icons.settings_outlined, Icons.settings, SettingsPage()),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bgmStarted) return;
    _bgmStarted = true;
    final AppState state = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 尊重「启动自动播放」开关
      if (state.bgmAutoPlay) state.bgm.autoStart();
    });
  }

  void _go(int i) {
    setState(() => _index = i);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = context.select<AppState, bool>((AppState s) => s.ready);
    if (!ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return AppBackground(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 1000;
          return Stack(
            children: <Widget>[
              if (wide)
                _wideScaffold(context, constraints.maxWidth >= 1280)
              else
                _narrowScaffold(context),
              const Positioned(right: 20, bottom: 24, child: BgmFab()),
            ],
          );
        },
      ),
    );
  }

  Widget _wideScaffold(BuildContext context, bool extended) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: extended,
            minWidth: 76,
            minExtendedWidth: 208,
            selectedIndex: _index,
            onDestinationSelected: _go,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: _destinations
                .map(
                  (_Destination d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18, left: 8, right: 8),
                  child: _railFooter(context, extended),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _railFooter(BuildContext context, bool extended) {
    final AppState state = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (extended) const AdminStatusTile(compact: true),
        const SizedBox(height: 8),
        if (state.unlocked)
          IconButton(
            tooltip: '锁定编辑（回到只读模式）',
            onPressed: state.lock,
            icon: const Icon(Icons.lock_outline),
            color: AppColors.textMuted,
          )
        else
          IconButton(
            tooltip: '解锁编辑',
            onPressed: () => showUnlockDialog(context),
            icon: const Icon(Icons.lock_open_outlined),
            color: AppColors.goldDeep,
          ),
        IconButton(
          tooltip: '设置',
          onPressed: () => _go(_destinations.length - 1),
          icon: const Icon(Icons.settings_outlined),
          color: AppColors.textMuted,
        ),
      ],
    );
  }

  Widget _narrowScaffold(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_destinations[_index].label),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: state.unlocked
                  ? IconButton(
                      tooltip: '锁定编辑',
                      onPressed: state.lock,
                      icon: const Icon(
                        Icons.lock_open_rounded,
                        color: AppColors.jade,
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => showUnlockDialog(context),
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: const Text('解锁'),
                    ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xF20C1426),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0x33F7E2A8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '落云宗',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 26,
                        letterSpacing: 6,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '宗门管理系统',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              for (int i = 0; i < _destinations.length; i++)
                ListTile(
                  leading: Icon(
                    i == _index
                        ? _destinations[i].selectedIcon
                        : _destinations[i].icon,
                    color: i == _index ? AppColors.gold : AppColors.textMuted,
                  ),
                  title: Text(
                    _destinations[i].label,
                    style: TextStyle(
                      color: i == _index ? AppColors.gold : AppColors.text,
                    ),
                  ),
                  selected: i == _index,
                  onTap: () => _go(i),
                ),
            ],
          ),
        ),
      ),
      body: _content(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index > 3 ? 4 : _index,
        onDestinationSelected: (int i) {
          if (i == 4) {
            _scaffoldKey.currentState?.openDrawer();
            return;
          }
          _go(i);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.groups_2_outlined),
            label: '名单',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            label: '排行',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            label: '成绩',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: '更多'),
        ],
      ),
    );
  }

  Widget _content() {
    return IndexedStack(
      index: _index,
      children: _destinations.map((_Destination d) => d.page).toList(),
    );
  }
}
