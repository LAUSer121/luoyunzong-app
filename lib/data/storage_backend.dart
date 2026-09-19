/// 存储后端抽象：桌面/移动写文件，Web 回退到浏览器存储。
///
/// 通过条件导入选择实现：非 Web 平台用 `storage_backend_io.dart`，
/// Web 平台用 `storage_backend_prefs.dart`。业务层只依赖本文件的接口。
library;

import 'storage_backend_prefs.dart'
    if (dart.library.io) 'storage_backend_io.dart'
    as impl;

abstract class StorageBackend {
  /// 读取存档文本；不存在返回 `null`。
  Future<String?> read();

  /// 覆盖写入存档文本。
  Future<void> write(String data);

  /// 删除存档。
  Future<void> delete();

  /// 后端描述，用于界面展示（如「本地文件」/「浏览器存储」）。
  String get description;

  /// 存档位置的可读描述（Web 端返回 `null`）。
  Future<String?> location() async => null;

  /// 写入「同步前快照」（冲突时保留另一份，便于恢复）。
  Future<void> writeSnapshot(String data) async {}

  /// 读取同步前快照。
  Future<String?> readSnapshot() async => null;
}

/// 创建当前平台的存储后端。
StorageBackend createStorageBackend() => impl.createStorageBackend();
