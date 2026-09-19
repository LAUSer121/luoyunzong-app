/// 本地仓储：把存档 JSON 落到文件（桌面/移动）或浏览器存储（Web）。
library;

import 'dart:async';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'archive_codec.dart';
import 'storage_backend.dart';

class LocalRepository implements LuoyunRepository {
  LocalRepository({StorageBackend? backend})
    : _backend = backend ?? createStorageBackend();

  final StorageBackend _backend;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  String get label => '本地存档';

  /// 存档位置（Web 端为 `null`）。
  Future<String?> location() => _backend.location();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Archive?> load() async {
    final String? text = await _backend.read();
    if (text == null || text.trim().isEmpty) return null;
    return ArchiveCodec.decode(text);
  }

  @override
  Future<void> save(Archive archive) async {
    await _backend.write(ArchiveCodec.encodeJson(archive));
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> clear() async {
    await _backend.delete();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// 写入同步前快照（冲突时保留另一份数据，便于恢复）。
  Future<void> writeSnapshot(String json) => _backend.writeSnapshot(json);

  /// 读取同步前快照。
  Future<String?> readSnapshot() => _backend.readSnapshot();

  void dispose() => _changes.close();
}
