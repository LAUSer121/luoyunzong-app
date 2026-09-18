/// 文件选择与保存：桌面/移动/Web 统一入口（底层 file_picker 13）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 选择单个文件并读取字节（Web 端同样可用）。
Future<PickedBytes?> pickBytes({
  required List<String> extensions,
  String? dialogTitle,
}) async {
  final PlatformFile? file = await FilePicker.pickFile(
    type: extensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
    dialogTitle: dialogTitle,
  );
  if (file == null) return null;
  final Uint8List bytes = await file.readAsBytes();
  return PickedBytes(file.name, bytes);
}

/// 选择多个文件（用于一次性添加多首 BGM）。
Future<List<PickedBytes>> pickMultipleBytes({
  required List<String> extensions,
  String? dialogTitle,
}) async {
  final List<PlatformFile> files = await FilePicker.pickFiles(
    type: extensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
    dialogTitle: dialogTitle,
  );
  final List<PickedBytes> out = <PickedBytes>[];
  for (final PlatformFile file in files) {
    out.add(PickedBytes(file.name, await file.readAsBytes()));
  }
  return out;
}

/// 保存文本文件；返回保存位置（Web 端返回下载的 object URL，失败返回 `null`）。
Future<String?> saveTextFile({
  required String fileName,
  required String content,
}) {
  return _save(
    fileName,
    Uint8List.fromList(utf8.encode(content)),
    'application/json',
  );
}

/// 保存二进制文件（导出立绘/视频时使用）。
Future<String?> saveBinaryFile({
  required String fileName,
  required Uint8List bytes,
}) {
  return _save(fileName, bytes, 'application/octet-stream');
}

Future<String?> _save(String fileName, Uint8List bytes, String mimeType) async {
  final Uri? uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: '导出文件',
  );
  return uri?.toString();
}

class PickedBytes {
  const PickedBytes(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}
