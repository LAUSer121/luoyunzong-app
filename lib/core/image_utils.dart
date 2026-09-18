/// 图片处理：把用户选择的图片压缩成 JPEG data URL（与旧版 canvas 压缩等价）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'constants.dart';

/// 压缩并编码为 `data:image/jpeg;base64,...`。
///
/// 失败返回 `null`，调用方据此提示「图片读取失败」。
String? compressImageToDataUrl(
  Uint8List bytes, {
  int maxWidth = kAvatarMaxWidth,
  int quality = kImageQuality,
}) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final img.Image resized = decoded.width <= maxWidth
        ? decoded
        : img.copyResize(
            decoded,
            width: maxWidth,
            interpolation: img.Interpolation.average,
          );
    final Uint8List jpg = img.encodeJpg(resized, quality: quality.toInt());
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return null;
  }
}

/// 把 data URL 还原成字节（用于视频/立绘导出）。
Uint8List? dataUrlToBytes(String dataUrl) {
  final int comma = dataUrl.indexOf(',');
  if (comma == -1) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// 是否为图片/视频 data URL。
bool isDataUrl(String? value) => value != null && value.startsWith('data:');
