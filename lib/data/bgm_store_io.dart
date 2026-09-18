/// BGM 文件仓库（桌面/移动）：应用支持目录 /bgm。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

bool get bgmStorageSupported => true;

Future<Directory> _dir() async {
  final Directory base = await getApplicationSupportDirectory();
  final Directory dir = Directory('${base.path}${Platform.pathSeparator}bgm');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

String _sanitize(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

Future<String?> storeAudioFile(String name, List<int> bytes) async {
  try {
    final Directory dir = await _dir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${_sanitize(name)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<bool> audioFileExists(String name) async =>
    (await audioFilePath(name)) != null;

Future<String?> audioFilePath(String name) async {
  try {
    final Directory dir = await _dir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${_sanitize(name)}',
    );
    return await file.exists() ? file.path : null;
  } catch (_) {
    return null;
  }
}

Future<List<String>> listAudioFiles() async {
  try {
    final Directory dir = await _dir();
    return dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toList();
  } catch (_) {
    return <String>[];
  }
}

Future<void> deleteAudioFile(String name) async {
  try {
    final Directory dir = await _dir();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}${_sanitize(name)}',
    );
    if (await file.exists()) await file.delete();
  } catch (_) {
    // 忽略删除失败
  }
}
