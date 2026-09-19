/// 设置：权限、背景、BGM、存档管理、数据源（本地 / MySQL API）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../bgm/bgm_player.dart';
import '../../core/constants.dart';
import '../../core/file_utils.dart';
import '../../core/image_utils.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/settings_store.dart';
import '../../data/wallpaper_client.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../state/sync_manager.dart';
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
  final TextEditingController _neteaseController = TextEditingController();
  final TextEditingController _defaultTrackController = TextEditingController();
  String? _storagePath;
  bool _storagePathRequested = false;
  String? _apiStatus;
  bool _apiBusy = false;
  bool _bgBusy = false;
  bool _useRemote = false;
  bool _loadedSettings = false;
  bool _defaultTrackSeeded = false;

  // ---- 云端资源存储（管理员）----
  final TextEditingController _storageEndpoint = TextEditingController();
  final TextEditingController _storageRegion = TextEditingController();
  final TextEditingController _storageBucket = TextEditingController();
  final TextEditingController _storageAccessKey = TextEditingController();
  final TextEditingController _storageSecretKey = TextEditingController();
  final TextEditingController _storagePublicBase = TextEditingController();
  final TextEditingController _storageOperator = TextEditingController();
  final TextEditingController _videoMaxMB = TextEditingController();
  final TextEditingController _videoMaxSeconds = TextEditingController();
  final TextEditingController _imageMaxMB = TextEditingController();
  String _storageDriver = 'local';
  bool _storageSecretSet = false;
  bool _storageLoaded = false;
  bool _storageLoading = false;
  bool _storageBusy = false;
  bool? _storageStatusOk;
  String? _storageStatus;

  Future<void> _loadStorageConfig() async {
    final AppState? state = mounted ? context.read<AppState>() : null;
    final ApiClient? client = state?.cloudClient;
    if (client == null) {
      if (mounted) setState(() => _storageLoaded = true);
      return;
    }
    try {
      final Map<String, Object?> cfg = await client.fetchStorageConfig();
      if (!mounted) return;
      setState(() {
        _storageDriver = '${cfg['driver'] ?? 'local'}';
        _storageEndpoint.text = '${cfg['endpoint'] ?? ''}';
        _storageRegion.text = '${cfg['region'] ?? ''}';
        _storageBucket.text = '${cfg['bucket'] ?? ''}';
        _storageAccessKey.text = '${cfg['accessKey'] ?? ''}';
        _storagePublicBase.text = '${cfg['publicBase'] ?? ''}';
        _storageOperator.text = '${cfg['upyunOperator'] ?? ''}';
        _storageSecretSet =
            cfg['secretKeySet'] == true || cfg['upyunPasswordSet'] == true;
        _applyLimits(cfg['limits']);
        _storageLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storageLoaded = true;
        _storageStatusOk = false;
        _storageStatus = client.friendlyError(e);
      });
    }
  }

  /// 组装当前表单内容；密钥留空时不下发（服务端保持原值）。
  /// 上传上限三个框 → 服务端字段。
  Map<String, Object?> _limitsPayload() => <String, Object?>{
    'videoMaxMB': int.tryParse(_videoMaxMB.text.trim()) ?? 20,
    'videoMaxSeconds': int.tryParse(_videoMaxSeconds.text.trim()) ?? 25,
    'imageMaxMB': int.tryParse(_imageMaxMB.text.trim()) ?? 20,
  };

  /// 用服务端返回的 limits 刷新三个输入框（所有设备即时生效）。
  void _applyLimits(Object? raw) {
    if (raw is! Map) return;
    final int videoMB = (raw['videoMaxMB'] as num?)?.toInt() ?? 20;
    final int seconds = (raw['videoMaxSeconds'] as num?)?.toInt() ?? 25;
    final int imageMB = (raw['imageMaxMB'] as num?)?.toInt() ?? 20;
    _videoMaxMB.text = videoMB.toString();
    _videoMaxSeconds.text = seconds.toString();
    _imageMaxMB.text = imageMB.toString();
  }

  Map<String, Object?> _storagePayload() {
    final String secret = _storageSecretKey.text.trim();
    if (_storageDriver == 's3') {
      return <String, Object?>{
        'driver': 's3',
        'endpoint': _storageEndpoint.text.trim(),
        'region': _storageRegion.text.trim(),
        'bucket': _storageBucket.text.trim(),
        'accessKey': _storageAccessKey.text.trim(),
        'publicBase': _storagePublicBase.text.trim(),
        if (secret.isNotEmpty) 'secretKey': secret,
        'limits': _limitsPayload(),
      };
    }
    if (_storageDriver == 'upyun') {
      return <String, Object?>{
        'driver': 'upyun',
        'bucket': _storageBucket.text.trim(),
        'upyunOperator': _storageOperator.text.trim(),
        'publicBase': _storagePublicBase.text.trim(),
        if (secret.isNotEmpty) 'upyunPassword': secret,
        'limits': _limitsPayload(),
      };
    }
    return <String, Object?>{'driver': 'local', 'limits': _limitsPayload()};
  }

  Future<void> _saveStorageConfig(AppState state, {bool silent = false}) async {
    final ApiClient? client = state.cloudClient;
    if (client == null) return;
    setState(() {
      _storageBusy = true;
      _storageStatus = null;
    });
    try {
      final Map<String, Object?> saved = await client.saveStorageConfig(
        _storagePayload(),
      );
      if (!mounted) return;
      setState(() {
        _storageBusy = false;
        _storageStatusOk = true;
        _secretKeysetFrom(saved);
        _applyLimits(saved['limits']);
        _storageStatus =
            '已保存到服务器：${saved['driver']}'
            '${(saved['bucket'] ?? '') == '' ? '' : ' · ${saved['bucket']}'}'
            '　|　上传上限：视频 ${state.videoMaxMB}MB / '
            '${state.videoMaxSeconds == 0 ? '不限时长' : '${state.videoMaxSeconds} 秒'}'
            '　（新上传的资源就进这里；已存在的资源位置不变）';
      });
      // 让其它页面（选视频时的校验）立刻用上新上限
      state.refreshUploadLimits();
      if (!silent) return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storageBusy = false;
        _storageStatusOk = false;
        _storageStatus = client.friendlyError(e);
      });
      rethrow;
    }
  }

  /// 统一更新「密钥是否已保存」的状态位。
  void _secretKeysetFrom(Map<String, Object?> saved) {
    _storageSecretSet =
        saved['secretKeySet'] == true || saved['upyunPasswordSet'] == true;
    _storageSecretKey.clear();
  }

  /// 测试连接：**先保存再测**，否则测的还是上一次存进去的老配置。
  Future<void> _testStorageConfig(AppState state) async {
    final ApiClient? client = state.cloudClient;
    if (client == null) return;
    try {
      await _saveStorageConfig(state, silent: true);
    } catch (_) {
      return; // 保存失败时已经把原因显示出来了，不必再测
    }
    if (!mounted) return;
    setState(() {
      _storageBusy = true;
      _storageStatus = null;
    });
    final ({bool ok, String message}) r = await client.testStorage();
    if (!mounted) return;
    setState(() {
      _storageBusy = false;
      _storageStatusOk = r.ok;
      _storageStatus = r.message;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 管理员工具：强制用本机覆盖云端。
  Future<void> _forcePush(AppState state, SyncManager sync) async {
    final bool? ok = await _confirm(
      title: '用本机存档覆盖云端？',
      body:
          '会把云端存档**整个替换**成本机内容（不看时间戳）。\n'
          '覆盖前云端那一份会自动备份到本机快照，随时可以恢复。',
      confirmText: '覆盖云端',
      danger: true,
    );
    if (ok != true) return;
    final SyncResult r = await sync.forcePushLocal();
    _toast(r.message);
  }

  /// 管理员工具：强制用云端覆盖本机。
  Future<void> _forcePull(AppState state, SyncManager sync) async {
    final bool? ok = await _confirm(
      title: '用云端存档覆盖本机？',
      body:
          '会把本机存档**整个替换**成云端内容（不看时间戳）。\n'
          '覆盖前本机那一份会自动备份到本机快照，随时可以恢复。',
      confirmText: '覆盖本机',
      danger: true,
    );
    if (ok != true) return;
    final SyncResult r = await sync.forcePullRemote();
    _toast(r.message);
  }

  /// 管理员工具：重置云端（清空云端存档，可选连资源一起清）。
  Future<void> _resetCloud(AppState state, SyncManager sync) async {
    bool includeAssets = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) =>
            AlertDialog(
              title: const Text('重置云端？'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '会清空云端存档（云端那份先备份到本机快照）。\n'
                    '清空后会自动关掉「自动同步」，避免刚清完又被推回去。',
                    style: TextStyle(fontSize: 13, height: 1.8),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeAssets,
                    onChanged: (bool? v) =>
                        setLocal(() => includeAssets = v ?? false),
                    title: const Text(
                      '同时清空云端资源（头像 / 立绘 / 背景 / 视频）',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      '只删数据库索引；对象存储里的文件可在缤纷云控制台按 luoyunzong/ 前缀批量清理',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: const Color(0xFF2A0D0D),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('重置云端'),
                ),
              ],
            ),
      ),
    );
    if (ok != true) return;
    final SyncResult r = await sync.resetCloud(includeAssets: includeAssets);
    _toast(r.message);
  }

  /// 统一的二次确认弹窗。
  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmText,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.8)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: const Color(0xFF2A0D0D),
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final String url = await _store.apiBaseUrl();
    final String token = await _store.apiToken();
    final String netease = await _store.neteaseBase();
    final bool useRemote = await _store.useRemote();
    if (!mounted) return;
    setState(() {
      _apiUrl.text = url;
      _apiToken.text = token;
      _neteaseController.text = netease;
      _useRemote = useRemote;
      _loadedSettings = true;
    });
  }

  @override
  void dispose() {
    _apiUrl.dispose();
    _apiToken.dispose();
    _neteaseController.dispose();
    _defaultTrackController.dispose();
    _storageEndpoint.dispose();
    _storageRegion.dispose();
    _storageBucket.dispose();
    _storageAccessKey.dispose();
    _storageSecretKey.dispose();
    _storagePublicBase.dispose();
    _storageOperator.dispose();
    _videoMaxMB.dispose();
    _videoMaxSeconds.dispose();
    _imageMaxMB.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 搜索并设置默认音乐：选中哪首就存哪首；没选（或搜不到）也把名称存进存档。
  Future<void> _pickDefaultTrack(AppState state, String query) async {
    final String text = query.trim();
    if (text.isEmpty) {
      _toast('先输入歌名，例如：不凡 王铮亮');
      return;
    }
    final OnlineTrack? picked = await showDefaultTrackPicker(
      context,
      state,
      initialQuery: text,
    );
    if (!mounted) return;
    if (picked == null) {
      // 只保存名称：至少让云端记住「默认音乐叫什么」。
      state.setDefaultTrackQuery(text);
      _toast('已保存默认音乐名称：$text（未绑定在线曲目）');
      return;
    }
    state.setDefaultTrack(picked, query: text);
    _defaultTrackController.text = state.defaultTrackQuery;
    _toast('默认音乐已设为：${picked.name} · ${picked.artist}');
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Archive archive = state.archive;
    final bool unlocked = state.unlocked;

    // 默认音乐输入框：首帧用存档里的名称填充一次（之后交给用户编辑）。
    if (!_defaultTrackSeeded && state.ready) {
      _defaultTrackSeeded = true;
      _defaultTrackController.text = state.defaultTrackQuery;
    }

    if (_storagePath == null && !_storagePathRequested) {
      _storagePathRequested = true;
      // 放到帧后异步读取，避免在 build 过程中触发 setState。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final String? p = await state.storageLocation();
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
        _bgmCard(state),
        const SizedBox(height: 16),
        _backgroundCard(state, archive),
        const SizedBox(height: 16),
        _archiveCard(state, unlocked),
        const SizedBox(height: 16),
        _syncCard(state),
        _cloudStorageCard(state),
        _dataSourceCard(state),
        const SizedBox(height: 16),
        _aboutCard(state),
      ],
    );
  }

  /// 云端资源存储（缤纷云 / 又拍云 / S3）——**只有管理员解锁后才显示**。
  ///
  /// 配置存在服务端 MySQL 的 app_settings 里；保存后新上传的头像/立绘/背景/视频
  /// 就直接进对象存储，数据库只留索引。密钥只存服务端，界面永远不回明文。
  Widget _cloudStorageCard(AppState state) {
    final ApiClient? client = state.cloudClient;
    if (client == null || !state.unlocked) return const SizedBox.shrink();

    if (!_storageLoaded && !_storageLoading) {
      _storageLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStorageConfig());
    }

    final bool s3 = _storageDriver == 's3';
    final bool upyun = _storageDriver == 'upyun';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            '云端资源存储',
            subtitle: '头像 / 立绘 / 背景 / 视频放这里；保存后写入服务端 MySQL，新上传立刻生效',
          ),
          if (!_storageLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('正在读取服务端配置…', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else ...<Widget>[
            DropdownButtonFormField<String>(
              initialValue: _storageDriver,
              decoration: const InputDecoration(labelText: '存储位置'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'local',
                  child: Text('服务端本地磁盘'),
                ),
                DropdownMenuItem<String>(
                  value: 's3',
                  child: Text('缤纷云 / S3 兼容对象存储'),
                ),
                DropdownMenuItem<String>(value: 'upyun', child: Text('又拍云')),
              ],
              onChanged: (String? v) =>
                  setState(() => _storageDriver = v ?? _storageDriver),
            ),
            const SizedBox(height: 12),
            if (s3) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _storageEndpoint,
                      decoration: const InputDecoration(
                        labelText: 'Endpoint',
                        hintText: 'https://s3.bitiful.net',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _storageRegion,
                      decoration: const InputDecoration(
                        labelText: 'Region',
                        hintText: 'cn-east-1',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _storageBucket,
                      decoration: const InputDecoration(labelText: '桶名 Bucket'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _storagePublicBase,
                      decoration: const InputDecoration(
                        labelText: '公开域名（可选）',
                        hintText: '留空＝由服务端中转',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _storageAccessKey,
                      decoration: const InputDecoration(
                        labelText: 'Access Key',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _storageSecretKey,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Secret Key',
                        hintText: _storageSecretSet ? '已保存，留空＝不修改' : '必填',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (upyun) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _storageBucket,
                      decoration: const InputDecoration(
                        labelText: '服务名 Bucket',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _storageOperator,
                      decoration: const InputDecoration(labelText: '操作员'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storageSecretKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '操作员密码',
                  hintText: _storageSecretSet ? '已保存，留空＝不修改' : '必填',
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ---- 上传上限（视频 / 图片；管理员可调，所有设备都按这个走）----
            const Text(
              '上传上限',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _videoMaxMB,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '视频单文件上限（MB）',
                      hintText: '例如 60',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _videoMaxSeconds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '视频时长上限（秒）',
                      hintText: '0 = 不限',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _imageMaxMB,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '图片上限（MB）',
                      hintText: '例如 30',
                    ),
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
                  onPressed: _storageBusy
                      ? null
                      : () => _saveStorageConfig(state),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_storageBusy ? '处理中…' : '保存到服务器'),
                ),
                OutlinedButton.icon(
                  onPressed: _storageBusy
                      ? null
                      : () => _testStorageConfig(state),
                  icon: const Icon(Icons.cloud_done_outlined, size: 18),
                  label: const Text('测试连接'),
                ),
              ],
            ),
            if (_storageStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _storageStatus!,
                  style: TextStyle(
                    color: (_storageStatusOk ?? false)
                        ? AppColors.jade
                        : AppColors.danger,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              '缤纷云填法：Endpoint https://s3.bitiful.net、Region cn-east-1、'
              '桶名与子账户的 Access Key / Secret Key。\n'
              '子账户必须先在缤纷云控制台「子账户&Key」里被授予该桶的读写权限，'
              '否则会报 AccessDenied（可点「测试连接」验证）。\n'
              '密钥只保存在服务端数据库，App 里不会显示；公开域名留空则资源由服务端中转。',
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 12,
                height: 1.9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 云同步卡片：把本地改动同步到云端、把云端信息同步回本机。
  ///
  /// 「自动同步」开关与上次同步时间保存在**本机设备**（不随存档同步到其他设备），
  /// 卡片里不出现任何服务端地址、数据库等细节。
  Widget _syncCard(AppState state) {
    final SyncManager? sync = state.sync;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sync,
      builder: (BuildContext context, Widget? _) {
        final bool failed = sync.lastFailed;
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionTitle('云端同步', subtitle: '本地修改上传云端 · 云端信息同步到本机'),
              Row(
                children: <Widget>[
                  Icon(
                    sync.syncing
                        ? Icons.sync
                        : failed
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                    size: 20,
                    color: failed
                        ? AppColors.danger
                        : (sync.syncing ? AppColors.goldDeep : AppColors.jade),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sync.statusLabel,
                      style: TextStyle(
                        color: failed ? AppColors.danger : AppColors.text,
                        fontSize: 13,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sync.autoSync,
                onChanged: (bool v) async {
                  await sync.setAutoSync(v);
                  _toast(v ? '已开启自动同步云端' : '已关闭自动同步');
                },
                title: const Text('自动同步云端', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '本机有修改或云端有更新时自动对齐（此开关只保存在本机设备）',
                  style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: sync.syncing
                        ? null
                        : () async {
                            final SyncResult r = await sync.syncNow();
                            _toast(r.message);
                          },
                    icon: Icon(
                      sync.syncing ? Icons.sync : Icons.cloud_sync_outlined,
                      size: 18,
                    ),
                    label: Text(sync.syncing ? '同步中…' : '立即同步'),
                  ),
                  OutlinedButton.icon(
                    onPressed: sync.syncing
                        ? null
                        : () => _restoreSnapshot(state, sync),
                    icon: const Icon(Icons.history_outlined, size: 18),
                    label: const Text('恢复上次同步前的备份'),
                  ),
                ],
              ),
              // ---- 管理员工具（危险操作，仅解锁管理员后显示）----
              const SizedBox(height: 18),
              Divider(color: AppColors.outline.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 16,
                    color: AppColors.goldDeep,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '管理员工具',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.unlocked
                          ? '强制覆盖 / 重置云端，操作前都有二次确认，且会自动备份'
                          : '解锁管理员后可用（右上角「只读模式」处解锁）',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: state.unlocked && !sync.syncing
                        ? () => _forcePush(state, sync)
                        : null,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text('本机覆盖云端'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.unlocked && !sync.syncing
                        ? () => _forcePull(state, sync)
                        : null,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('云端覆盖本机'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.unlocked && !sync.syncing
                        ? () => _resetCloud(state, sync)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.6),
                      ),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text('重置云端'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 冲突时落败的那一份会留在本机快照里，这里让用户能一键找回。
  Future<void> _restoreSnapshot(AppState state, SyncManager sync) async {
    final Archive? snap = await sync.snapshotArchive();
    if (!mounted) return;
    if (snap == null) {
      _toast('暂无可恢复的备份（同步起冲突时才会自动留一份）');
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('恢复上次同步前的备份？'),
        content: const Text('当前内容会被这份备份覆盖，请确认。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.applyRemoteArchive(snap);
    await state.markSyncedAt(DateTime.now());
    if (!mounted) return;
    _toast('已恢复备份内容');
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

  /// 音乐与电台设置：自动播放开关、在线搜索代理地址。
  Widget _bgmCard(AppState state) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(
            '音乐与在线电台',
            subtitle: '曲单、封面与进度条在右下角音乐悬浮球里；这里配置启动行为与代理',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.bgmAutoPlay,
            onChanged: state.setBgmAutoPlay,
            title: const Text('进入应用后自动播放 BGM', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '关闭后需手动点开音乐悬浮球播放',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.useDefaultTrack,
            onChanged: state.setUseDefaultTrack,
            title: const Text('启用默认音乐', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              state.useDefaultTrack
                  ? '当前：${state.defaultTrack.name} · ${state.defaultTrack.artist}'
                        '（曲单第一首，自动播放时先放它）'
                  : '已关闭：不再自动把默认音乐放进曲单',
              style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _defaultTrackController,
                  decoration: const InputDecoration(
                    labelText: '默认音乐',
                    hintText: '输入歌名或「歌名 歌手」，例如：不凡 王铮亮',
                  ),
                  onSubmitted: (String v) => _pickDefaultTrack(state, v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () =>
                    _pickDefaultTrack(state, _defaultTrackController.text),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('搜索并设为默认'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '开关和这个名称都保存在存档里，会跟着云同步到其它设备；'
            '搜索只是把歌名对上在线曲库（拿到 id 才能播放），失败也能只保存名称。',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _neteaseController,
                  enabled: _loadedSettings,
                  decoration: const InputDecoration(
                    labelText: '在线电台代理地址（可选）',
                    hintText: 'http://127.0.0.1:3000（自建 NeteaseCloudMusicApi）',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  await _store.setNeteaseBase(_neteaseController.text);
                  state.setNeteaseBase(_neteaseController.text);
                  _toast('在线电台代理已保存');
                },
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '网易云搜索：桌面/手机版直连官方接口；浏览器版受跨域限制，需填写自建代理地址。'
            '在线曲目只保存歌名/歌手/封面，播放时按 id 取流地址。',
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
                    ? () => _pickLocalBackground(state)
                    : null,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('导入本地照片（相册）'),
              ),
              FilledButton.icon(
                onPressed: _bgBusy ? null : () => _fetchOnlineBackground(state),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(_bgBusy ? '正在获取…' : '换一张在线仙侠背景'),
              ),
            ],
          ),
          // ---- 背景相册：导入过的照片都在这儿，点一下就能切 ----
          if (archive.background.gallery.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text(
                  '我的背景相册',
                  style: TextStyle(color: AppColors.gold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '${archive.background.gallery.length} 张 · 随存档同步到云端',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: archive.background.gallery.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (BuildContext ctx, int i) {
                  final String photo = archive.background.gallery[i];
                  final bool current = archive.background.data == photo;
                  return _bgThumb(
                    photo: photo,
                    current: current,
                    canDelete: state.unlocked,
                    onTap: () {
                      state.selectBackgroundPhoto(photo);
                      _toast('已切换到这张背景');
                    },
                    onDelete: () {
                      state.removeBackgroundPhoto(photo);
                      _toast('已从相册移除');
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: archive.background.autoOnline,
            onChanged: state.setAutoOnlineBackground,
            title: const Text('启动时自动获取在线仙侠背景', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '每次打开应用联网换一张（水墨山水 / 云雾仙山 / 古刹 / 江湖 等标签随机）',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '想指定题材就点下面标签直接换：',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WallpaperClient.presetQueries
                .map(
                  (String tag) => ActionChip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    onPressed: _bgBusy
                        ? null
                        : () => _fetchOnlineBackground(state, query: tag),
                  ),
                )
                .toList(),
          ),
          if (archive.background.credit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                archive.background.credit,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 导入本地照片：存进「背景相册」并立刻设为当前背景（照片随存档同步到云端）。
  Future<void> _pickLocalBackground(AppState state) async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      dialogTitle: '选择背景照片',
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
    state.addBackgroundPhoto(data);
    _toast('已导入背景相册并设为当前背景（会随存档同步到云端）');
  }

  /// 相册缩略图：点一下切换，右上角小叉删除（仅管理员）。
  Widget _bgThumb({
    required String photo,
    required bool current,
    required bool canDelete,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    final Uint8List? bytes = dataUrlToBytes(photo);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Tooltip(
          message: current ? '当前背景' : '点一下用这张',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 148,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: current ? AppColors.gold : AppColors.outline,
                  width: current ? 2 : 1,
                ),
                color: const Color(0x33101A2E),
                boxShadow: current
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.28),
                          blurRadius: 12,
                          spreadRadius: -3,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 18,
                        color: AppColors.textFaint,
                      ),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ),
        if (current)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xCC0B1226),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.6),
                ),
              ),
              child: const Text(
                '当前',
                style: TextStyle(color: AppColors.gold, fontSize: 10),
              ),
            ),
          ),
        if (canDelete)
          Positioned(
            right: -6,
            top: -6,
            child: Tooltip(
              message: '从相册移除',
              child: InkWell(
                onTap: onDelete,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xF21B2030),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _fetchOnlineBackground(AppState state, {String? query}) async {
    setState(() => _bgBusy = true);
    final String? error = await state.fetchOnlineBackground(query: query);
    if (!mounted) return;
    setState(() => _bgBusy = false);
    _toast(error ?? '已换上一张在线仙侠背景');
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

  /// 数据源卡片：
  /// - 默认只显示一个状态行（云端同步 / 本地存档），**不暴露任何服务端地址或数据库信息**；
  /// - 仅当打包时加了 --dart-define=LUOYUNZONG_SHOW_SERVER_CONFIG=true，才在解锁后出现可编辑配置。
  Widget _dataSourceCard(AppState state) {
    final bool cloud = state.storageLabel.contains('云端');
    if (!AppConfig.showServerConfig) {
      return GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionTitle('数据存储', subtitle: '存档与资源自动保存，无需手动操作'),
            Row(
              children: <Widget>[
                Icon(
                  cloud ? Icons.cloud_done_outlined : Icons.smartphone_outlined,
                  size: 20,
                  color: cloud ? AppColors.jade : AppColors.goldDeep,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cloud
                        ? '云端同步已开启（断网时自动回落本地存档，恢复后继续同步）'
                        : '当前使用本地存档（数据保存在本机，可导出备份）',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle('数据源（调试入口）', subtitle: '当前：${state.storageLabel}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useRemote,
            onChanged: _loadedSettings
                ? (bool v) async {
                    setState(() => _useRemote = v);
                    await _store.setUseRemote(v);
                    _toast(v ? '已开启云端同步（重启后生效）' : '已切回本地模式（重启后生效）');
                  }
                : null,
            title: const Text('使用云端同步', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '存档与资源保存到服务端；断网自动回落本地存档',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
          const SizedBox(height: 6),
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
                        await _store.setUseRemote(_useRemote);
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
