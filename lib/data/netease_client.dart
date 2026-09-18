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
    final Object? result = json['result'];
    if (result is! Map) return <OnlineTrack>[];
    final List<Object?> songs =
        (result['songs'] as List<Object?>?) ?? const <Object?>[];
    return songs.map(_songFromPublic).whereType<OnlineTrack>().toList();
  }

  /// 解析 cloudsearch/pc 的歌曲结构（`ar` / `al` / `dt`）。
  OnlineTrack? _songFromPublic(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> song = raw.cast<String, Object?>();
    final String id = '${song['id'] ?? ''}';
    if (id.isEmpty) return null;
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
    final Object? result = json['result'];
    if (result is! Map) return <OnlineTrack>[];
    final List<Object?> songs =
        (result['songs'] as List<Object?>?) ?? const <Object?>[];
    return songs
        .map((Object? raw) {
          if (raw is! Map) return null;
          final Map<String, Object?> song = raw.cast<String, Object?>();
          final String id = '${song['id'] ?? ''}';
          if (id.isEmpty) return null;
          String artist = '';
          final Object? ar = song['ar'] ?? song['artists'];
          if (ar is List) {
            artist = ar
                .whereType<Map<Object?, Object?>>()
                .map((Map<Object?, Object?> a) => '${a['name'] ?? ''}')
                .where((String s) => s.isNotEmpty)
                .join(' / ');
          }
          String cover = '';
          final Object? al = song['al'] ?? song['album'];
          if (al is Map) cover = '${al['picUrl'] ?? ''}';
          return OnlineTrack(
            id: id,
            name: '${song['name'] ?? '未知曲目'}',
            artist: artist,
            cover: cover,
            durationMs:
                (song['dt'] as num?)?.toInt() ??
                (song['duration'] as num?)?.toInt() ??
                0,
          );
        })
        .whereType<OnlineTrack>()
        .toList();
  }

  /// 取可播放流地址；受版权限制 / 需要会员时返回 `null`。
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
    // 官方外链：能播放时 302 到 mp3；不可播放（VIP / 下架）会返回一个 HTML 提示页。
    final String candidate =
        'https://music.163.com/song/media/outer/url?id=$id.mp3';
    try {
      final http.Request req = http.Request('GET', Uri.parse(candidate))
        ..headers.addAll(_publicHeaders)
        ..headers['Range'] = 'bytes=0-0';
      final http.StreamedResponse res = await _client
          .send(req)
          .timeout(const Duration(seconds: 15));
      final String type = (res.headers['content-type'] ?? '').toLowerCase();
      await res.stream.drain<void>();
      if (type.contains('text/html')) return null;
      return candidate;
    } catch (_) {
      // 网络异常时仍返回直链，交给播放器报错
      return candidate;
    }
  }

  /// 封面小图地址（网易云支持 `?param=WxH` 裁剪）。
  static String coverUrl(OnlineTrack track, {int size = 120}) {
    if (track.cover.isEmpty) return '';
    return '${track.cover}?param=${size}y$size';
  }

  void close() => _client.close();
}
