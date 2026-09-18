/// 应用设置持久化（与存档分离：这些是本机偏好，不随存档导出）。
library;

import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const String _kApiBaseUrl = 'luoyunzong_api_base_url';
  static const String _kApiToken = 'luoyunzong_api_token';
  static const String _kUseRemote = 'luoyunzong_use_remote';
  static const String _kMuted = 'luoyunzong_bgm_muted';
  static const String _kNeteaseBase = 'luoyunzong_netease_base';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 网易云在线搜索代理地址（自建 NeteaseCloudMusicApi，用于绕过 Web 端跨域）。
  Future<String> neteaseBase() async =>
      (await _prefs).getString(_kNeteaseBase) ?? '';

  Future<void> setNeteaseBase(String value) async =>
      (await _prefs).setString(_kNeteaseBase, value.trim());

  Future<String> apiBaseUrl() async =>
      (await _prefs).getString(_kApiBaseUrl) ?? '';

  Future<void> setApiBaseUrl(String value) async =>
      (await _prefs).setString(_kApiBaseUrl, value.trim());

  Future<String> apiToken() async => (await _prefs).getString(_kApiToken) ?? '';

  Future<void> setApiToken(String value) async =>
      (await _prefs).setString(_kApiToken, value.trim());

  Future<bool> useRemote() async =>
      (await _prefs).getBool(_kUseRemote) ?? false;

  Future<void> setUseRemote(bool value) async =>
      (await _prefs).setBool(_kUseRemote, value);

  Future<bool> bgmMuted() async => (await _prefs).getBool(_kMuted) ?? false;

  Future<void> setBgmMuted(bool value) async =>
      (await _prefs).setBool(_kMuted, value);
}
