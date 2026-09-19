/// 大体积资源的拆分与还原：把存档里的 base64 data URL（头像 / 立绘 / 动态视频 / 背景图）
/// 抽成独立资源，存档里只留 `asset:<id>` 引用。
///
/// 目的：接云端 MySQL 时，存档 JSON 保持轻量（同步快），图片与视频单独走资源表 / 对象存储。
/// 本地存储不需要拆分，仍然整包保存（导入导出与旧版兼容）。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';

/// 资源引用的前缀。
const String kAssetScheme = 'asset:';

/// 一个待上传的资源。
class AssetPayload {
  const AssetPayload({
    required this.id,
    required this.bytes,
    required this.mime,
  });

  /// 资源 id：内容的 sha256 前 32 位十六进制（天然去重）。
  final String id;
  final Uint8List bytes;
  final String mime;

  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

/// 拆分结果。
class AssetSplit {
  const AssetSplit({required this.archive, required this.assets});

  /// 已经用 `asset:<id>` 替换过大资源引用的存档。
  final Archive archive;

  /// 需要单独上传的资源（按 id 去重）。
  final List<AssetPayload> assets;

  int get totalBytes =>
      assets.fold<int>(0, (int sum, AssetPayload a) => sum + a.bytes.length);
}

/// 判断是否为资源引用。
bool isAssetRef(String? value) =>
    value != null && value.startsWith(kAssetScheme);

/// 取资源 id。
String? assetRefId(String? value) {
  if (!isAssetRef(value)) return null;
  final String id = value!.substring(kAssetScheme.length).trim();
  return id.isEmpty ? null : id;
}

/// 把 data URL 解析成字节与 MIME；不是 data URL 返回 `null`。
({Uint8List bytes, String mime})? decodeDataUrl(String? value) {
  if (value == null || !value.startsWith('data:')) return null;
  final int comma = value.indexOf(',');
  if (comma < 0) return null;
  final String meta = value.substring(5, comma);
  final String mime = meta.split(';').first.trim().isEmpty
      ? 'application/octet-stream'
      : meta.split(';').first.trim();
  final bool isBase64 = meta.contains('base64');
  try {
    final String payload = value.substring(comma + 1);
    final Uint8List bytes = isBase64
        ? base64Decode(payload)
        : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
    return (bytes: bytes, mime: mime);
  } catch (_) {
    return null;
  }
}

/// 资源 id：内容哈希（两个 31 位哈希 + 长度），相同内容天然去重。
///
/// 注意必须用 **31 位**运算：Web 端 dart2js 的整数只有 53 位安全范围，
/// 64 位字面量（如 FNV-1a 的 0xcbf29ce484222325）会直接编译失败。
/// 这里用 djb2 与 sdbm 各算一遍（一个正序一个倒序），中间量都 < 2^47，安全。
String assetIdOf(Uint8List bytes) {
  int djb2 = 5381; // djb2 种子
  for (final int b in bytes) {
    djb2 = ((djb2 * 33) ^ b) & 0x7FFFFFFF;
  }
  int sdbm = 0;
  for (int i = bytes.length - 1; i >= 0; i--) {
    sdbm = (bytes[i] + (sdbm << 6) + (sdbm << 16) - sdbm) & 0x7FFFFFFF;
  }
  String hex8(int v) => v.toRadixString(16).padLeft(8, '0');
  return '${hex8(djb2)}${hex8(sdbm)}${bytes.length.toRadixString(16)}';
}

/// 把存档里超过 [thresholdBytes] 的资源拆出来；小于阈值的保持内联（省一次请求）。
AssetSplit splitAssets(Archive archive, {int thresholdBytes = 48 * 1024}) {
  final Map<String, AssetPayload> assets = <String, AssetPayload>{};

  String? refFor(String? value) {
    final ({Uint8List bytes, String mime})? decoded = decodeDataUrl(value);
    if (decoded == null) return value;
    if (decoded.bytes.length <= thresholdBytes) return value;
    final String id = assetIdOf(decoded.bytes);
    assets.putIfAbsent(
      id,
      () => AssetPayload(id: id, bytes: decoded.bytes, mime: decoded.mime),
    );
    return '$kAssetScheme$id';
  }

  // 复制一份，避免直接改到内存中的存档对象
  final Archive copy = archive.copy();
  for (final Member m in copy.memberList) {
    m.avatar = refFor(m.avatar);
    m.portrait = refFor(m.portrait);
    m.video = refFor(m.video);
  }
  for (final Peak p in copy.peakList) {
    p.avatar = refFor(p.avatar);
  }
  final BackgroundSetting bg = copy.background;
  if (bg.type == BgType.image && bg.data != null) {
    final String? ref = refFor(bg.data);
    if (ref != bg.data) {
      copy.background = BackgroundSetting(
        type: BgType.image,
        data: ref,
        credit: bg.credit,
        autoOnline: bg.autoOnline,
      );
    }
  }

  return AssetSplit(archive: copy, assets: assets.values.toList());
}

/// 用已下载的资源把引用还原成 data URL；缺失的资源保持引用不变（界面显示占位符）。
Archive restoreAssets(Archive archive, Map<String, Uint8List> assets) {
  final Archive copy = archive.copy();

  String? restore(String? value) {
    final String? id = assetRefId(value);
    if (id == null) return value;
    final Uint8List? bytes = assets[id];
    if (bytes == null) return value;
    return 'data:${_guessMime(bytes)};base64,${base64Encode(bytes)}';
  }

  for (final Member m in copy.memberList) {
    m.avatar = restore(m.avatar);
    m.portrait = restore(m.portrait);
    m.video = restore(m.video);
  }
  for (final Peak p in copy.peakList) {
    p.avatar = restore(p.avatar);
  }
  final BackgroundSetting bg = copy.background;
  if (bg.type == BgType.image && bg.data != null) {
    final String? data = restore(bg.data);
    if (data != bg.data) {
      copy.background = BackgroundSetting(
        type: BgType.image,
        data: data,
        credit: bg.credit,
        autoOnline: bg.autoOnline,
      );
    }
  }
  return copy;
}

/// 收集存档里引用到的资源 id（用于批量拉取）。
Set<String> referencedAssetIds(Archive archive) {
  final Set<String> ids = <String>{};
  void add(String? value) {
    final String? id = assetRefId(value);
    if (id != null) ids.add(id);
  }

  for (final Member m in archive.memberList) {
    add(m.avatar);
    add(m.portrait);
    add(m.video);
  }
  for (final Peak p in archive.peakList) {
    add(p.avatar);
  }
  add(archive.background.data);
  return ids;
}

/// 按文件头猜测 MIME（服务端未返回时使用）。
String _guessMime(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79) {
    return 'video/mp4';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  return 'application/octet-stream';
}
