/// 应用设置持久化（与存档分离：这些是本机偏好，不随存档导出）。
///
/// 支持构建期烧入默认云端地址：
///   flutter build apk --dart-define=LUOYUNZONG_API_BASE=https://api.example.com \
///                     --dart-define=LUOYUNZONG_API_TOKEN=xxxx
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

class SettingsStore {
  static const String _kApiBaseUrl = 'luoyunzong_api_base_url';
  static const String _kApiToken = 'luoyunzong_api_token';
  static const String _kUseRemote = 'luoyunzong_use_remote';
  static const String _kMuted = 'luoyunzong_bgm_muted';
  static const String _kNeteaseBase = 'luoyunzong_netease_base';
  static const String _kAutoSync = 'luoyunzong_auto_sync';
  static const String _kLastSyncAt = 'luoyunzong_last_sync_at';
  static const String _kLastLocalChange = 'luoyunzong_last_local_change';
  static const String _kDbPassword = 'luoyunzong_db_password';

  /// 构建期注入的默认服务端地址与令牌（未注入时为空串）。
  static const String bakedApiBase = String.fromEnvironment(
    'LUOYUNZONG_API_BASE',
  );
  static const String bakedApiToken = String.fromEnvironment(
    'LUOYUNZONG_API_TOKEN',
  );

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 服务端地址：优先用户设置，其次构建期烧入值。
  Future<String> apiBaseUrl() async {
    final String saved = (await _prefs).getString(_kApiBaseUrl) ?? '';
    return saved.isNotEmpty ? saved : bakedApiBase;
  }

  Future<void> setApiBaseUrl(String value) async =>
      (await _prefs).setString(_kApiBaseUrl, value.trim());

  Future<String> apiToken() async {
    final String saved = (await _prefs).getString(_kApiToken) ?? '';
    return saved.isNotEmpty ? saved : bakedApiToken;
  }

  Future<void> setApiToken(String value) async =>
      (await _prefs).setString(_kApiToken, value.trim());

  /// 是否使用云端同步；构建期烧了地址时默认开启。
  Future<bool> useRemote() async {
    final bool? saved = (await _prefs).getBool(_kUseRemote);
    if (saved != null) return saved;
    return bakedApiBase.isNotEmpty;
  }

  Future<void> setUseRemote(bool value) async =>
      (await _prefs).setBool(_kUseRemote, value);

  // ---- 云同步（保存在本机设备，不随存档同步到其他设备）----

  /// 是否自动同步云端。
  Future<bool> autoSync() async => (await _prefs).getBool(_kAutoSync) ?? false;

  Future<void> setAutoSync(bool value) async =>
      (await _prefs).setBool(_kAutoSync, value);

  Future<DateTime?> lastSyncAt() async {
    final int? ms = (await _prefs).getInt(_kLastSyncAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastSyncAt(DateTime at) async =>
      (await _prefs).setInt(_kLastSyncAt, at.millisecondsSinceEpoch);

  Future<DateTime?> lastLocalChangeAt() async {
    final int? ms = (await _prefs).getInt(_kLastLocalChange);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastLocalChangeAt(DateTime at) async =>
      (await _prefs).setInt(_kLastLocalChange, at.millisecondsSinceEpoch);

  /// 数据库口令：直连模式要用；只存本机（不烧进安装包、不同步到云端）。
  Future<String> dbPassword() async {
    final String saved = (await _prefs).getString(_kDbPassword) ?? '';
    return saved.isNotEmpty ? saved : AppConfig.dbPasswordBaked;
  }

  Future<void> setDbPassword(String value) async =>
      (await _prefs).setString(_kDbPassword, value.trim());

  Future<bool> bgmMuted() async => (await _prefs).getBool(_kMuted) ?? false;

  Future<void> setBgmMuted(bool value) async =>
      (await _prefs).setBool(_kMuted, value);

  /// 网易云在线搜索代理地址（自建 NeteaseCloudMusicApi，用于绕过 Web 端跨域）。
  Future<String> neteaseBase() async =>
      (await _prefs).getString(_kNeteaseBase) ?? '';

  Future<void> setNeteaseBase(String value) async =>
      (await _prefs).setString(_kNeteaseBase, value.trim());
}
