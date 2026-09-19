/// 桌面 / 移动端存储实现：写入应用支持目录下的存档文件。
///
/// 便携模式（单文件便携版）：满足任一条件时，存档与可执行文件放在一起
/// 1. 环境变量 `LUOYUNZONG_DATA_DIR` 指向某个目录；
/// 2. 可执行文件同级存在 `luoyunzong_data` 目录（解压版/绿色版用户自行创建即可）。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage_backend.dart';

const String _kFileName = 'luoyunzong_archive.json';
const String _kBackupName = 'luoyunzong_archive.backup.json';
const String _kSnapshotName = 'luoyunzong_archive.snapshot.json';

/// 便携模式数据目录名（与可执行文件同级）。
const String kPortableDataDirName = 'luoyunzong_data';

class FileStorageBackend implements StorageBackend {
  FileStorageBackend();

  File? _cached;

  @override
  String get description => '本地文件';

  /// 数据目录：便携目录优先，其次系统应用支持目录。
  Future<Directory> _baseDir() async {
    final String? envDir = Platform.environment['LUOYUNZONG_DATA_DIR'];
    if (envDir != null && envDir.trim().isNotEmpty) {
      final Directory dir = Directory(envDir.trim());
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    try {
      final Directory exeDir = File(Platform.resolvedExecutable).parent;
      final Directory portable = Directory(
        '${exeDir.path}${Platform.pathSeparator}$kPortableDataDirName',
      );
      if (await portable.exists()) return portable;
    } catch (_) {
      // 桌面以外的平台忽略
    }
    return getApplicationSupportDirectory();
  }

  Future<File> _resolve() async {
    if (_cached != null) return _cached!;
    final Directory dir = await _baseDir();
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

  File? _snapshotFile() {
    final File? main = _cached;
    if (main == null) return null;
    return File('${main.parent.path}${Platform.pathSeparator}$_kSnapshotName');
  }

  @override
  Future<void> writeSnapshot(String data) async {
    await _resolve();
    final File? snap = _snapshotFile();
    if (snap == null) return;
    await snap.writeAsString(data, flush: true);
  }

  @override
  Future<String?> readSnapshot() async {
    await _resolve();
    final File? snap = _snapshotFile();
    if (snap == null || !await snap.exists()) return null;
    return snap.readAsString();
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
