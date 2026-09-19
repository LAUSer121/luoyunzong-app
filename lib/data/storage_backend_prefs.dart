/// Web / 无文件系统环境的存储实现：shared_preferences。
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'storage_backend.dart';

const String _kKey = 'luoyunzong_all';
const String _kBackupKey = 'luoyunzong_all_backup';
const String _kSnapshotKey = 'luoyunzong_all_snapshot';

class PrefsStorageBackend implements StorageBackend {
  @override
  String get description => '浏览器存储';

  @override
  Future<String?> location() async => null;

  @override
  Future<String?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_kKey);
  }

  @override
  Future<void> write(String data) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? previous = prefs.getString(_kKey);
    if (previous != null && previous.isNotEmpty) {
      await prefs.setString(_kBackupKey, previous);
    }
    await prefs.setString(_kKey, data);
  }

  @override
  Future<void> writeSnapshot(String data) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSnapshotKey, data);
  }

  @override
  Future<String?> readSnapshot() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_kSnapshotKey);
  }

  @override
  Future<void> delete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
    await prefs.remove(_kBackupKey);
  }
}

StorageBackend createStorageBackend() => PrefsStorageBackend();
