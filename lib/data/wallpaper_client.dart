/// 在线仙侠背景：多图源自动挑选（无需 API Key）。
///
/// 依次尝试，直到拿到一张能解码、宽度足够的图：
///   1. Wallhaven 公开 API（境外网络下最贴合仙侠/幻想插画）
///   2. 必应图片搜索（中文关键词「仙侠 壁纸 / 水墨山水」等，国内可达）
///   3. 必应每日壁纸（官方接口，稳定，多为自然风景/云海）
///   4. Picsum 随机图（最后的兜底，且允许跨域，浏览器端也能用）
///
/// 仅用于本机背景显示；图片作者/页面地址会写入存档 credit 字段便于署名。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class OnlineWallpaper {
  const OnlineWallpaper({
    required this.imageUrl,
    this.pageUrl = '',
    this.author = '',
    this.source = 'Wallhaven',
    this.resolution = '',
    this.tag = '',
  });

  final String imageUrl;
  final String pageUrl;
  final String author;
  final String source;
  final String resolution;
  final String tag;

  /// 展示用署名。
  String get credit {
    final String who = author.isEmpty ? '' : ' · $author';
    final String size = resolution.isEmpty ? '' : ' · $resolution';
    return '图片来自 $source$who$size';
  }
}

/// 一张已经下载并通过校验的图。
class WallpaperPick {
  const WallpaperPick(this.wallpaper, this.bytes);

  final OnlineWallpaper wallpaper;
  final Uint8List bytes;
}

class WallpaperException implements Exception {
  WallpaperException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WallpaperClient {
  WallpaperClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final math.Random _rnd = math.Random();

  /// 中文检索词（必应图片搜索用），设置页展示的就是这些。
  static const List<String> presetQueries = <String>[
    '仙侠 壁纸',
    '水墨山水 壁纸',
    '云雾仙山',
    '古风 山水 壁纸',
    '江湖 剑侠 壁纸',
    '仙山 云海 壁纸',
    '古刹 云雾 壁纸',
    '修真 仙侠 场景',
  ];

  /// 英文标签（Wallhaven 用英文标签命中率更高）。
  static const List<String> presetTags = <String>[
    'chinese landscape',
    'ink painting mountain',
    'misty mountains',
    'chinese temple',
    'fantasy mountain fog',
  ];

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Accept': 'application/json,text/html,image/*',
    'Referer': 'https://cn.bing.com/',
  };

  static const int _minWidth = 1200;

  /// Wallhaven 在国内通常不可达：失败一次后本次会话不再重试，避免每次都要等超时。
  bool _wallhavenUnavailable = false;

  /// 随机取一张可用的在线壁纸；全部图源失败返回 `null`。
  Future<WallpaperPick?> pick({String? query}) async {
    final String cn = (query == null || query.trim().isEmpty)
        ? presetQueries[_rnd.nextInt(presetQueries.length)]
        : query.trim();

    // 1) 必应图片搜索（国内可达，通常 1~3 秒出图）
    for (final OnlineWallpaper w in await _bingImageCandidates(cn)) {
      final WallpaperPick? pick = await _verify(w);
      if (pick != null) return pick;
    }
    // 2) 必应每日壁纸（稳定，风景/云海）
    for (final OnlineWallpaper w in await _bingDailyCandidates()) {
      final WallpaperPick? pick = await _verify(w);
      if (pick != null) return pick;
    }
    // 3) Wallhaven（境外网络下更贴合仙侠插画；国内不可达时只试一次）
    if (!_wallhavenUnavailable) {
      for (final OnlineWallpaper w in await _wallhavenCandidates(cn)) {
        final WallpaperPick? pick = await _verify(w);
        if (pick != null) return pick;
      }
    }
    // 4) Picsum 兜底
    return _verify(
      OnlineWallpaper(
        imageUrl:
            'https://picsum.photos/seed/lyz${_rnd.nextInt(9999)}/1920/1080',
        source: 'Picsum',
        resolution: '1920x1080',
        tag: cn,
      ),
    );
  }

  /// 下载 + 校验（能解码、宽度 >= 1200）。
  Future<WallpaperPick?> _verify(OnlineWallpaper wallpaper) async {
    final Uint8List? bytes = await download(wallpaper);
    if (bytes == null) return null;
    try {
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width < _minWidth) return null;
      return WallpaperPick(
        OnlineWallpaper(
          imageUrl: wallpaper.imageUrl,
          pageUrl: wallpaper.pageUrl,
          author: wallpaper.author,
          source: wallpaper.source,
          resolution: '${decoded.width}x${decoded.height}',
          tag: wallpaper.tag,
        ),
        bytes,
      );
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // 图源 1：Wallhaven
  // ------------------------------------------------------------------
  Future<List<OnlineWallpaper>> _wallhavenCandidates(String cn) async {
    final List<OnlineWallpaper> out = <OnlineWallpaper>[];
    final List<String> tags = List<String>.of(presetTags)..shuffle(_rnd);
    for (final String tag in tags.take(1)) {
      try {
        final Uri uri = Uri.https(
          'wallhaven.cc',
          '/api/v1/search',
          <String, String>{
            'q': tag,
            'categories': '100',
            'purity': '100',
            'sorting': 'random',
            'atleast': '1920x1080',
            'ratios': '16x9',
          },
        );
        final http.Response res = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) {
          _wallhavenUnavailable = true;
          continue;
        }
        final Map<String, Object?> json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
        final List<Object?> data =
            (json['data'] as List<Object?>?) ?? const <Object?>[];
        for (final Object? raw in data.take(6)) {
          if (raw is! Map) continue;
          final Map<String, Object?> item = raw.cast<String, Object?>();
          final String path = '${item['path'] ?? ''}';
          if (path.isEmpty) continue;
          String author = '';
          final Object? uploader = item['uploader'];
          if (uploader is Map) author = '${uploader['username'] ?? ''}';
          out.add(
            OnlineWallpaper(
              imageUrl: path,
              pageUrl: '${item['short_url'] ?? item['url'] ?? ''}',
              author: author,
              source: 'Wallhaven',
              resolution: '${item['resolution'] ?? ''}',
              tag: tag,
            ),
          );
        }
        if (out.isNotEmpty) break;
      } catch (_) {
        // 本图源不可达（国内常见）：本次会话不再重试
        _wallhavenUnavailable = true;
      }
    }
    out.shuffle(_rnd);
    return out;
  }

  // ------------------------------------------------------------------
  // 图源 2：必应图片搜索（解析 murl 直链）
  // ------------------------------------------------------------------
  Future<List<OnlineWallpaper>> _bingImageCandidates(String query) async {
    try {
      final Uri uri = Uri.https(
        'cn.bing.com',
        '/images/search',
        <String, String>{
          'q': query,
          'form': 'HDRSC2',
          'first': '1',
          'qft': '+filterui:imagesize-wallpaper+filterui:aspect-wide',
        },
      );
      final http.Response res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return <OnlineWallpaper>[];
      final String html = utf8.decode(res.bodyBytes, allowMalformed: true);
      final List<OnlineWallpaper> out = <OnlineWallpaper>[];
      final RegExp re = RegExp(r'murl&quot;:&quot;(https?://[^&]+?)&quot;');
      final Set<String> seen = <String>{};
      for (final RegExpMatch m in re.allMatches(html)) {
        final String url = m.group(1)!.replaceAll(r'\/', '/');
        if (!url.startsWith('https://')) continue; // 只用 https，避免明文被系统拦
        if (!seen.add(url)) continue;
        out.add(OnlineWallpaper(imageUrl: url, source: '必应图片搜索', tag: query));
      }
      out.shuffle(_rnd);
      return out.take(12).toList();
    } catch (_) {
      return <OnlineWallpaper>[];
    }
  }

  // ------------------------------------------------------------------
  // 图源 3：必应每日壁纸
  // ------------------------------------------------------------------
  Future<List<OnlineWallpaper>> _bingDailyCandidates() async {
    try {
      final Uri uri = Uri.https(
        'cn.bing.com',
        '/HPImageArchive.aspx',
        <String, String>{'format': 'js', 'idx': '0', 'n': '8', 'mkt': 'zh-CN'},
      );
      final http.Response res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return <OnlineWallpaper>[];
      final Map<String, Object?> json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
      final List<Object?> images =
          (json['images'] as List<Object?>?) ?? const <Object?>[];
      final List<OnlineWallpaper> out = <OnlineWallpaper>[];
      for (final Object? raw in images) {
        if (raw is! Map) continue;
        final Map<String, Object?> item = raw.cast<String, Object?>();
        final String base = '${item['urlbase'] ?? ''}';
        if (base.isEmpty) continue;
        out.add(
          OnlineWallpaper(
            imageUrl: 'https://cn.bing.com${base}_1920x1080.jpg',
            pageUrl: '${item['copyrightlink'] ?? ''}',
            author: '${item['copyright'] ?? ''}',
            source: '必应每日壁纸',
            resolution: '1920x1080',
            tag: '每日壁纸',
          ),
        );
      }
      out.shuffle(_rnd);
      return out;
    } catch (_) {
      return <OnlineWallpaper>[];
    }
  }

  /// 下载图片字节。
  Future<Uint8List?> download(
    OnlineWallpaper wallpaper, {
    int maxBytes = 20 * 1024 * 1024,
  }) async {
    try {
      final http.Response res = await _client
          .get(Uri.parse(wallpaper.imageUrl), headers: _headers)
          .timeout(const Duration(seconds: 35));
      if (res.statusCode != 200) return null;
      final Uint8List bytes = res.bodyBytes;
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
