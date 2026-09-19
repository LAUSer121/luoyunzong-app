/// 应用设置持久化（与存档分离：这些是本机偏好，不随存档导出）。
///
/// 支持构建期烧入默认云端地址：
///   flutter build apk --dart-define=LUOYUNZONG_API_BASE=https://api.example.com \
///                     --dart-define=LUOYUNZONG_API_TOKEN=xxxx
library;

import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const String _kApiBaseUrl = 'luoyunzong_api_base_url';
  static const String _kApiToken = 'luoyunzong_api_token';
  static const String _kUseRemote = 'luoyunzong_use_remote';
  static const String _kMuted = 'luoyunzong_bgm_muted';
  static const String _kNeteaseBase = 'luoyunzong_netease_base';

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

  Future<bool> bgmMuted() async => (await _prefs).getBool(_kMuted) ?? false;

  Future<void> setBgmMuted(bool value) async =>
      (await _prefs).setBool(_kMuted, value);

  /// 网易云在线搜索代理地址（自建 NeteaseCloudMusicApi，用于绕过 Web 端跨域）。
  Future<String> neteaseBase() async =>
      (await _prefs).getString(_kNeteaseBase) ?? '';

  Future<void> setNeteaseBase(String value) async =>
      (await _prefs).setString(_kNeteaseBase, value.trim());
}
