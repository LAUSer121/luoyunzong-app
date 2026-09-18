/// 网易云音乐在线搜索（“修仙电台”）。
///
/// - 桌面 / 手机：直接调用 music.163.com 的公开接口；
/// - Web：浏览器跨域限制会拦下请求，可在设置里填写自建
///   [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) 地址（如
///   `http://127.0.0.1:3000`）作为代理，本客户端会自动切换到代理接口。
///
/// 只返回元数据与可播放流地址，不下载、不缓存受版权保护的内容。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';

class NeteaseException implements Exception {
  NeteaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NeteaseClient {
  NeteaseClient({String apiBase = '', http.Client? client})
    : apiBase = apiBase.trim().replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  /// 自建代理地址（空则直连官方接口）。
  final String apiBase;
  final http.Client _client;

  bool get useProxy => apiBase.isNotEmpty;

  /// 修仙 / 古风 风格的预设搜索词。
  static const List<String> presetKeywords = <String>[
    '仙侠',
    '古风',
    '仙气纯音乐',
    '洞箫古筝',
    '御剑江湖',
    '宗门修炼',
    '山河仙途',
    '打坐冥想',
  ];

  static const Map<String, String> _publicHeaders = <String, String>{
    'Referer': 'https://music.163.com/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Cookie': 'appver=2.10.6; os=pc',
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  /// 搜索歌曲。
  Future<List<OnlineTrack>> search(String keyword, {int limit = 30}) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) return <OnlineTrack>[];
    try {
      if (useProxy) return await _searchViaProxy(kw, limit);
      return await _searchPublic(kw, limit);
    } on NeteaseException {
      rethrow;
    } catch (e) {
      throw NeteaseException('搜索失败：$e');
    }
  }

  Future<List<OnlineTrack>> _searchPublic(String kw, int limit) async {
    // 用 cloudsearch/pc：它带封面（al.picUrl）与歌手（ar[].name）；
    // search/get/web 的同名字段是空的，会导致列表没有封面。
    final http.Response res = await _client
        .post(
          Uri.parse('https://music.163.com/api/cloudsearch/pc'),
          headers: _publicHeaders,
          body: <String, String>{
            's': kw,
            'type': '1',
            'offset': '0',
            'limit': '$limit',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw NeteaseException('网易云返回 ${res.statusCode}');
    }
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    return parseSearchResponse(json);
  }

  /// 解析搜索响应（官方 cloudsearch/pc 与自建代理 `/search` 结构一致）：
  /// `result.songs[].ar[].name` / `al.picUrl` / `dt`。
  static List<OnlineTrack> parseSearchResponse(Map<String, Object?> json) {
    final Object? result = json['result'];
    if (result is! Map) return <OnlineTrack>[];
    final List<Object?> songs =
        (result['songs'] as List<Object?>?) ?? const <Object?>[];
    return songs.map(_songFromJson).whereType<OnlineTrack>().toList();
  }

  static OnlineTrack? _songFromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> song = raw.cast<String, Object?>();
    final String id = '${song['id'] ?? ''}';
    // 网易云偶发返回 id=0 的占位条目，直接跳过。
    if (id.isEmpty || id == '0') return null;
    final List<Object?> artists =
        (song['ar'] as List<Object?>?) ?? const <Object?>[];
    final String artist = artists
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> a) => '${a['name'] ?? ''}')
        .where((String s) => s.isNotEmpty)
        .join(' / ');
    String cover = '';
    final Object? album = song['al'];
    if (album is Map) cover = '${album['picUrl'] ?? ''}';
    return OnlineTrack(
      id: id,
      name: '${song['name'] ?? '未知曲目'}',
      artist: artist,
      cover: cover,
      durationMs: (song['dt'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<OnlineTrack>> _searchViaProxy(String kw, int limit) async {
    final Uri uri = Uri.parse('$apiBase/search').replace(
      queryParameters: <String, String>{'keywords': kw, 'limit': '$limit'},
    );
    final http.Response res = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw NeteaseException('代理返回 ${res.statusCode}');
    }
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    return parseSearchResponse(json);
  }

  /// 取可播放流地址（**已跟随跳转的直链**）；受版权限制 / 需要会员时返回 `null`。
  ///
  /// 注意：必须返回最终 CDN 直链。Windows 上用 Media Foundation 播放，
  /// 如果给它 302 跳转地址（`.../outer/url?id=x.mp3` 这种没有扩展名的 URL），
  /// 会直接报 `WindowsAudioError: Failed to set source`。
  Future<String?> streamUrl(String id) async {
    if (useProxy) {
      try {
        final Uri uri = Uri.parse('$apiBase/song/url')
            .replace(queryParameters: <String, String>{'id': id});
        final http.Response res = await _client
            .get(uri)
            .timeout(const Duration(seconds: 15));
        final Map<String, Object?> json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
        final List<Object?> data =
            (json['data'] as List<Object?>?) ?? const <Object?>[];
        if (data.isNotEmpty && data.first is Map) {
          final Object? url = (data.first as Map<Object?, Object?>)['url'];
          if (url is String && url.isNotEmpty) return url;
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    final String candidate =
        'https://music.163.com/song/media/outer/url?id=$id.mp3';
    try {
      // 手动跟随跳转（package:http 的 StreamedResponse 不暴露跳转历史），
      // 直到拿到真正的 CDN 直链——Windows 的 Media Foundation 只认直链。
      String current = candidate;
      for (int hop = 0; hop < 4; hop++) {
        final http.Request req = http.Request('GET', Uri.parse(current))
          ..followRedirects = false
          ..headers.addAll(_publicHeaders)
          ..headers['Range'] = 'bytes=0-0';
        final http.StreamedResponse res = await _client
            .send(req)
            .timeout(const Duration(seconds: 15));
        final String type = (res.headers['content-type'] ?? '').toLowerCase();
        await res.stream.drain<void>();

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final String? location = res.headers['location'];
          if (location == null || location.isEmpty) return null;
          current = Uri.parse(current).resolve(location).toString();
          continue;
        }
        if (res.statusCode != 200 && res.statusCode != 206) return null;
        // 不可播放（VIP / 下架）时网易云返回 HTML 提示页
        if (type.contains('text/html')) return null;
        return current;
      }
      return current;
    } catch (_) {
      return null;
    }
  }

  /// 直接下载音频字节（播放器不支持流时的兜底，例如部分 Windows 环境）。
  Future<Uint8List?> downloadBytes(
    String url, {
    int maxBytes = 16 * 1024 * 1024,
  }) async {
    try {
      final http.Response res = await _client
          .get(Uri.parse(url), headers: _publicHeaders)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      if (res.bodyBytes.isEmpty || res.bodyBytes.length > maxBytes) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// 封面小图地址（网易云支持 `?param=WxH` 裁剪）。
  static String coverUrl(OnlineTrack track, {int size = 120}) {
    if (track.cover.isEmpty) return '';
    return '${track.cover}?param=${size}y$size';
  }

  void close() => _client.close();
}
