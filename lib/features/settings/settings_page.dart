/// 设置：权限、背景、BGM、存档管理、数据源（本地 / MySQL API）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/image_utils.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/settings_store.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../widgets/admin_bar.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/page_body.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsStore _store = SettingsStore();
  final TextEditingController _apiUrl = TextEditingController();
  final TextEditingController _apiToken = TextEditingController();
  String? _storagePath;
  String? _apiStatus;
  bool _apiBusy = false;
  bool _loadedSettings = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final String url = await _store.apiBaseUrl();
    final String token = await _store.apiToken();
    if (!mounted) return;
    setState(() {
      _apiUrl.text = url;
      _apiToken.text = token;
      _loadedSettings = true;
    });
  }

  @override
  void dispose() {
    _apiUrl.dispose();
    _apiToken.dispose();
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

    if (_storagePath == null) {
      state.storageLocation().then((String? p) {
        if (mounted && p != null) setState(() => _storagePath = p);
      });
    }

    return PageBody(
      maxWidth: 1080,
      children: <Widget>[
        PageHeader(
          title: '设置',
          subtitle: '权限 · 背景 · BGM · 存档 · 数据源',
          actions: <Widget>[AdminStatusTile(compact: true)],
        ),
        _permissionCard(state, unlocked),
        const SizedBox(height: 16),
        _backgroundCard(state, archive),
        const SizedBox(height: 16),
        _archiveCard(state, unlocked),
        const SizedBox(height: 16),
        _dataSourceCard(state),
        const SizedBox(height: 16),
        _aboutCard(state),
      ],
    );
  }

  Widget _permissionCard(AppState state, bool unlocked) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('权限', subtitle: '未解锁时为只读模式，仅可浏览与导出'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              AdminStatusTile(),
              FilledButton.icon(
                onPressed: unlocked
                    ? () {
                        state.lock();
                        _toast('已回到只读模式');
                      }
                    : () async {
                        final bool ok = await showUnlockDialog(context);
                        if (ok) _toast('已解锁编辑');
                      },
                icon: Icon(
                  unlocked ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 18,
                ),
                label: Text(unlocked ? '锁定编辑' : '解锁编辑'),
              ),
              OutlinedButton.icon(
                onPressed: unlocked
                    ? () => showChangePasswordDialog(context)
                    : null,
                icon: const Icon(Icons.password_outlined, size: 18),
                label: const Text('修改管理员密码'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '提示：管理员密码保存在存档中（默认 123456）。接入 MySQL 后可切换为服务端校验。',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _backgroundCard(AppState state, Archive archive) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle('背景', subtitle: '当前：${archive.background.label}'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _bgOption(
                state: state,
                label: '默认背景',
                selected: archive.background.isDefault,
                colors: <Color>[const Color(0xFF0B1734), AppColors.backdrop],
                onTap: () {
                  state.resetBackground();
                  _toast('已恢复默认背景');
                },
              ),
              for (final BgPreset p in kBgPresets)
                _bgOption(
                  state: state,
                  label: p.name,
                  selected:
                      archive.background.type == BgType.preset &&
                      archive.background.key == p.key,
                  colors: <Color>[Color(p.beginColor), Color(p.endColor)],
                  onTap: () {
                    state.setBackgroundPreset(p.key);
                    _toast('背景已切换：${p.name}');
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: state.unlocked
                    ? () async {
                        final PickedBytes? picked = await pickBytes(
                          extensions: <String>[
                            'png',
                            'jpg',
                            'jpeg',
                            'webp',
                            'bmp',
                          ],
                          dialogTitle: '选择背景图片',
                        );
                        if (picked == null) return;
                        final String? data = compressImageToDataUrl(
                          picked.bytes,
                          maxWidth: kBackgroundMaxWidth,
                          quality: 85,
                        );
                        if (data == null) {
                          _toast('图片读取失败');
                          return;
                        }
                        state.setBackgroundImage(data);
                        _toast('背景已更换');
                      }
                    : null,
                icon: const Icon(Icons.wallpaper_outlined, size: 18),
                label: const Text('选择本地图片'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bgOption({
    required AppState state,
    required String label,
    required bool selected,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: state.unlocked ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Container(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.gold : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveCard(AppState state, bool unlocked) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(
            '存档',
            subtitle:
                '当前后端：${state.storageLabel}'
                '${_storagePath == null ? '' : ' · $_storagePath'}',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: unlocked
                    ? () async {
                        await state.flush();
                        _toast('存档已保存');
                      }
                    : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('立即保存'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final String? path = await saveTextFile(
                    fileName: '落云宗存档.js',
                    content: state.exportJs(),
                  );
                  if (path != null) _toast('已导出旧版兼容存档：$path');
                },
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('导出存档（.js）'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final String? path = await saveTextFile(
                    fileName: '落云宗存档.json',
                    content: state.exportJson(),
                  );
                  if (path != null) _toast('已导出 JSON 存档：$path');
                },
                icon: const Icon(Icons.data_object, size: 18),
                label: const Text('导出 JSON'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final PickedBytes? picked = await pickBytes(
                    extensions: <String>['json', 'js', 'txt'],
                    dialogTitle: '选择存档文件',
                  );
                  if (picked == null) return;
                  final String text = utf8.decode(
                    picked.bytes,
                    allowMalformed: true,
                  );
                  final String? err = state.importArchiveText(text);
                  _toast(err ?? '存档导入成功');
                },
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入存档'),
              ),
              OutlinedButton.icon(
                onPressed: unlocked
                    ? () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: const Text('清空全部数据'),
                            content: const Text(
                              '将删除名单、通天塔、山峰、成绩、背景与 BGM 曲单，密码保留。',
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
          const SizedBox(height: 12),
          const Text(
            '存档格式与旧版网页互通：导出的 .js 可被旧页面直接读取，旧页面的「落云宗存档.js」也可直接导入本应用。',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataSourceCard(AppState state) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            '数据源（后期接入 MySQL）',
            subtitle: '当前为本地模式；填写服务端地址后即可切换到 HTTP + MySQL 后端',
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _apiUrl,
                  enabled: _loadedSettings,
                  decoration: const InputDecoration(
                    labelText: '服务端地址',
                    hintText:
                        'https://example.com/api 或 http://192.168.1.10:8080',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _apiToken,
                  enabled: _loadedSettings,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '访问令牌（可选）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _apiBusy
                    ? null
                    : () async {
                        setState(() => _apiBusy = true);
                        await _store.setApiBaseUrl(_apiUrl.text);
                        await _store.setApiToken(_apiToken.text);
                        final ApiClient client = ApiClient(
                          baseUrl: _apiUrl.text.trim(),
                          token: _apiToken.text.trim(),
                        );
                        final bool ok = _apiUrl.text.trim().isEmpty
                            ? false
                            : await client.ping();
                        client.close();
                        if (!mounted) return;
                        setState(() {
                          _apiBusy = false;
                          _apiStatus = ok ? '连接成功：服务端可用' : '连接失败：请检查地址与网络';
                        });
                      },
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: Text(_apiBusy ? '测试中…' : '保存并测试连接'),
              ),
            ],
          ),
          if (_apiStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _apiStatus!,
                style: TextStyle(
                  color: _apiStatus!.startsWith('连接成功')
                      ? AppColors.jade
                      : AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            '接口约定（详见 docs/backend-mysql.md）：\n'
            'GET  /api/health · POST /api/auth/verify · GET|PUT|DELETE /api/archive\n'
            '服务端按存档整包读写，表结构由 docs/backend-mysql.md 的 schema.sql 提供。',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard(AppState state) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('关于', subtitle: '落云宗 · 宗门管理（Flutter 多端版）'),
          Text(
            '平台：${_platformName()}\n'
            '存档版本：v${state.archive.archiveVersion}\n'
            '成员 ${state.archive.memberList.length} 人 · 山峰 ${state.archive.peakList.length} 座 · '
            '通天塔 ${state.archive.towerList.length} 条 · 考试 ${state.archive.examData.sessions.length} 场\n'
            '数据保存在${state.storageLabel}${_storagePath == null ? '' : '：$_storagePath'}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.9,
            ),
          ),
          if (state.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.lastError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _platformName() {
    if (kIsWeb) return 'Web（浏览器）';
    return defaultTargetPlatform.name;
  }
}
