/// 桌面 / 移动端存储实现：写入应用支持目录下的存档文件。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage_backend.dart';

const String _kFileName = 'luoyunzong_archive.json';
const String _kBackupName = 'luoyunzong_archive.backup.json';

class FileStorageBackend implements StorageBackend {
  FileStorageBackend();

  File? _cached;

  @override
  String get description => '本地文件';

  Future<File> _resolve() async {
    if (_cached != null) return _cached!;
    final Directory dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File('${dir.path}${Platform.pathSeparator}$_kFileName');
    _cached = file;
    return file;
  }

  /// 当前存档路径，供设置页展示。
  Future<String> path() async => (await _resolve()).path;

  @override
  Future<String?> location() async => path();

  @override
  Future<String?> read() async {
    final File file = await _resolve();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String data) async {
    final File file = await _resolve();
    // 先写备份，再原子替换，避免写入中断导致存档损坏。
    if (await file.exists()) {
      try {
        await file.copy(
          '${file.parent.path}${Platform.pathSeparator}$_kBackupName',
        );
      } catch (_) {
        // 备份失败不阻断主流程
      }
    }
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    final File file = await _resolve();
    if (await file.exists()) await file.delete();
    final File backup = File(
      '${file.parent.path}${Platform.pathSeparator}$_kBackupName',
    );
    if (await backup.exists()) await backup.delete();
  }
}

StorageBackend createStorageBackend() => FileStorageBackend();
