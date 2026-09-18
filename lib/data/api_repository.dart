/// 远端仓储：通过 HTTP + MySQL 服务端读写存档。
///
/// 与 `LocalRepository` 实现同一接口，切换数据源时只需在 `main.dart`
/// 里改一行构造，界面与业务逻辑完全不动。
library;

import 'dart:async';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'api_client.dart';

class ApiRepository implements LuoyunRepository {
  ApiRepository({required this.client, this.fallback});

  final ApiClient client;

  /// 网络不可用时的本地兜底仓储（可选）。
  final LuoyunRepository? fallback;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _offline = false;

  @override
  String get label => _offline ? '${client.baseUrl}（离线兜底）' : client.baseUrl;

  bool get isOffline => _offline;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Archive?> load() async {
    try {
      final Archive? remote = await client.fetchArchive();
      _offline = false;
      return remote;
    } on Object {
      _offline = true;
      return fallback?.load();
    }
  }

  @override
  Future<void> save(Archive archive) async {
    try {
      await client.putArchive(archive);
      _offline = false;
    } on Object {
      _offline = true;
      await fallback?.save(archive);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> clear() async {
    try {
      await client.deleteArchive();
    } on Object {
      _offline = true;
    }
    await fallback?.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> verifyPassword(String password) async {
    try {
      return await client.verifyPassword(password);
    } on Object {
      return false;
    }
  }

  void dispose() {
    _changes.close();
    client.close();
  }
}
