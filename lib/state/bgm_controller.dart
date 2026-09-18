/// BGM 播放控制器：本地曲目 + 网易云在线曲目（带封面、可拖动进度）。
///
/// 音频后端（audioplayers）采用惰性创建：在没有平台插件的环境（单元测试、
/// 精简桌面环境）里只标记不可用，不让应用启动失败。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/bgm_store.dart';
import '../data/netease_client.dart';
import '../domain/models.dart';

class BgmTrack {
  BgmTrack({
    required this.name,
    this.path,
    this.bytes,
    this.sessionOnly = false,
    this.online,
    this.autoPicked = false,
  });

  final String name;
  String? path;

  /// 会话曲目（Web 端或临时文件时直接用内存播放）。
  Uint8List? bytes;
  final bool sessionOnly;

  /// 在线曲目（网易云）元数据。
  final OnlineTrack? online;

  /// 是否由「一键仙侠电台」自动挑选（下次自动挑选时会被替换）。
  final bool autoPicked;

  /// 已解析的流地址。
  String? remoteUrl;

  bool missing = false;

  bool get isOnline => online != null;

  String? get cover => online == null ? null : NeteaseClient.coverUrl(online!);

  String get subtitle {
    if (online != null) return online!.subtitle;
    if (sessionOnly) return '本次会话';
    if (missing) return '文件缺失';
    return '本地文件';
  }
}

class BgmController extends ChangeNotifier {
  BgmController();

  AudioPlayer? _player;
  bool _audioAvailable = true;
  bool _eventsBound = false;

  /// 在线搜索客户端（由 AppState 注入，含可选代理地址）。
  NeteaseClient? netease;

  final List<BgmTrack> _tracks = <BgmTrack>[];
  int _index = 0;
  double _volume = 0.6;
  bool _playing = false;
  bool _started = false;
  String? _lastError;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _resolving = false;

  List<BgmTrack> get tracks => List<BgmTrack>.unmodifiable(_tracks);
  int get index => _index;
  double get volume => _volume;
  bool get playing => _playing;
  bool get resolving => _resolving;
  String? get lastError => _lastError;
  bool get audioAvailable => _audioAvailable;
  Duration get duration => _duration;
  Duration get position => _position;
  double get progress => _duration.inMilliseconds == 0
      ? 0
      : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  BgmTrack? get current =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;
  String get title => current?.name ?? '未选择音乐';
  String? get currentCover => current?.cover;
  bool get storageSupported => bgmStorageSupported;

  /// 惰性获取播放器；平台不支持时返回 `null`。
  AudioPlayer? _ensurePlayer() {
    if (!_audioAvailable) return null;
    if (_player != null) {
      _bindEvents();
      return _player;
    }
    try {
      _player = AudioPlayer();
      _bindEvents();
      return _player;
    } catch (_) {
      _audioAvailable = false;
      _lastError = '当前环境不支持音频播放';
      return null;
    }
  }

  void _bindEvents() {
    if (_eventsBound || _player == null) return;
    _eventsBound = true;
    final AudioPlayer player = _player!;
    player.onPlayerComplete.listen((_) => unawaited(next(auto: true)));
    player.onDurationChanged.listen((Duration d) {
      _duration = d;
      notifyListeners();
    });
    player.onPositionChanged.listen((Duration p) {
      _position = p;
      notifyListeners();
    });
    player.onPlayerStateChanged.listen((PlayerState s) {
      _playing = s == PlayerState.playing;
      notifyListeners();
    });
  }

  /// 平台不支持音频（如单元测试、无音频后端的环境）时标记不可用。
  void markUnavailable() {
    _audioAvailable = false;
    _lastError = '当前环境不支持音频播放';
    _playing = false;
    notifyListeners();
  }

  /// 依据存档重建曲单：本地曲目 → 在线曲目 → 会话曲目。
  Future<void> syncFromArchive(Archive archive) async {
    final List<BgmTrack> sessionTracks = _tracks
        .where((BgmTrack t) => t.sessionOnly)
        .toList();

    _tracks
      ..clear()
      ..addAll(
        archive.bgm.customNames.map((String name) => BgmTrack(name: name)),
      )
      ..addAll(
        archive.bgm.onlineTracks.map(
          (OnlineTrack t) => BgmTrack(name: t.name, online: t),
        ),
      )
      ..addAll(sessionTracks);

    _volume = archive.bgm.volume;
    final AudioPlayer? player = _ensurePlayer();
    if (player != null) {
      try {
        await player.setVolume(_volume);
      } catch (_) {
        _audioAvailable = false;
      }
    }

    for (final BgmTrack t in _tracks) {
      if (!t.sessionOnly && !t.isOnline) {
        t.path = await audioFilePath(t.name);
        t.missing = t.path == null;
      }
    }
    _index = _tracks.isEmpty
        ? 0
        : archive.bgm.index.clamp(0, _tracks.length - 1);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 本地曲目管理
  // ------------------------------------------------------------------

  /// 添加本地音乐文件（复制到应用数据目录；Web 端为会话曲目）。
  Future<String?> addFiles(List<({String name, Uint8List bytes})> files) async {
    if (files.isEmpty) return '没有可用的音频文件';
    final List<String> addedNames = <String>[];
    for (final ({String name, Uint8List bytes}) f in files) {
      final String? path = await storeAudioFile(f.name, f.bytes);
      if (path != null) {
        _tracks.add(BgmTrack(name: f.name, path: path));
      } else {
        _tracks.add(BgmTrack(name: f.name, bytes: f.bytes, sessionOnly: true));
      }
      addedNames.add(f.name);
    }
    if (_tracks.isNotEmpty && !_playing && _index >= _tracks.length) {
      _index = _tracks.length - 1;
    }
    notifyListeners();
    return '已添加 ${addedNames.length} 首音乐';
  }

  /// 由文件名加入曲单（长期曲目）。
  Future<List<String>> addByName(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return <String>[];
    if (_tracks.any((BgmTrack t) => t.name == trimmed)) return <String>[];
    final String? path = await audioFilePath(trimmed);
    _tracks.add(BgmTrack(name: trimmed, path: path, sessionOnly: path == null));
    if (path == null) {
      _lastError = '未找到音乐文件：$trimmed（请先用「添加本地音乐」导入）';
    }
    notifyListeners();
    return <String>[trimmed];
  }

  /// 把在线曲目加入曲单（会写入存档）。
  void addOnlineTrack(OnlineTrack track) {
    if (_tracks.any((BgmTrack t) => t.isOnline && t.online!.id == track.id)) {
      return;
    }
    _tracks.add(BgmTrack(name: track.name, online: track));
    _index = _tracks.length - 1;
    notifyListeners();
  }

  /// 播放一首在线歌曲（不写入曲单，用于电台试听）。
  Future<void> playOnlinePreview(OnlineTrack track) async {
    final int exist = _tracks.indexWhere(
      (BgmTrack t) => t.isOnline && t.online!.id == track.id,
    );
    if (exist >= 0) {
      _index = exist;
    } else {
      _tracks.add(BgmTrack(name: track.name, online: track, sessionOnly: true));
      _index = _tracks.length - 1;
    }
    notifyListeners();
    await loadCurrent(autoplay: true);
  }

  Future<void> removeTrack(int i) async {
    if (i < 0 || i >= _tracks.length) return;
    final BgmTrack t = _tracks[i];
    if (!t.sessionOnly && !t.isOnline) await deleteAudioFile(t.name);
    _tracks.removeAt(i);
    if (_index > i) _index--;
    if (_tracks.isEmpty) {
      _index = 0;
      await stop();
    } else if (_index >= _tracks.length) {
      _index = _tracks.length - 1;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 播放控制
  // ------------------------------------------------------------------

  /// 一键挑选仙侠 / 古风曲目：随机关键词搜索，逐个校验可播放性，
  /// 挑到 [target] 首后替换上一轮自动挑选的曲目并可立即播放。
  /// 一键挑选仙侠 / 古风曲目：随机关键词搜索 + 逐个校验可播放性，
  /// 挑到 [target] 首后替换上一轮自动挑选的曲目并可立即播放。
  Future<String?> autoFillXianxia({bool playNow = true, int target = 6}) async {
    final NeteaseClient? client = netease;
    if (client == null) return '在线音乐客户端未就绪';
    _resolving = true;
    _lastError = null;
    notifyListeners();

    List<({OnlineTrack track, String url})> picked;
    try {
      picked = await client.pickPlayable(target: target);
    } finally {
      _resolving = false;
    }

    if (picked.isEmpty) {
      _lastError = '没有挑到可播放的仙侠曲目（网络或版权限制）';
      notifyListeners();
      return _lastError;
    }

    // 替换上一轮自动挑选的曲目（手动加入的曲单不动）
    _tracks.removeWhere((BgmTrack t) => t.autoPicked);
    final int firstIndex = _tracks.length;
    for (final ({OnlineTrack track, String url}) p in picked) {
      _tracks.add(
        BgmTrack(
          name: p.track.name,
          online: p.track,
          sessionOnly: true,
          autoPicked: true,
        )..remoteUrl = p.url,
      );
    }
    _index = firstIndex;
    _lastError = null;
    notifyListeners();
    if (playNow) await loadCurrent(autoplay: true);
    return '已自动挑选  首仙侠曲目';
  }

  Future<void> loadCurrent({bool autoplay = true}) async {
    final BgmTrack? t = current;
    if (t == null) {
      notifyListeners();
      return;
    }
    final AudioPlayer? player = _ensurePlayer();
    if (player == null) {
      _playing = false;
      notifyListeners();
      return;
    }
    try {
      if (t.isOnline) {
        _resolving = true;
        notifyListeners();
        t.remoteUrl ??= await netease?.streamUrl(t.online!.id);
        _resolving = false;
        final String? url = t.remoteUrl;
        if (url == null || url.isEmpty) {
          _lastError = '无法获取《${t.name}》的播放地址（可能受版权限制）';
          _playing = false;
          notifyListeners();
          return;
        }
        try {
          await player.play(
            UrlSource(url, mimeType: 'audio/mpeg'),
            volume: _volume,
          );
        } catch (e) {
          // Windows(Media Foundation) 对某些直链不买账：下载到内存再播。
          final Uint8List? bytes = await netease?.downloadBytes(url);
          if (bytes == null) rethrow;
          await player.play(BytesSource(bytes), volume: _volume);
        }
      } else if (t.path != null) {
        await player.play(DeviceFileSource(t.path!), volume: _volume);
      } else if (t.bytes != null) {
        await player.play(BytesSource(t.bytes!), volume: _volume);
      } else {
        t.missing = true;
        _lastError = '未找到音乐文件：${t.name}';
        notifyListeners();
        return;
      }
      _playing = autoplay;
      _lastError = null;
    } catch (e) {
      _resolving = false;
      _playing = false;
      _lastError = '播放失败：$e';
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_tracks.isEmpty) return;
    if (_playing) {
      try {
        await _player?.pause();
      } catch (_) {
        // 忽略
      }
      _playing = false;
      notifyListeners();
    } else {
      await loadCurrent(autoplay: true);
    }
  }

  Future<void> next({bool auto = false}) async {
    if (_tracks.isEmpty) return;
    _index = (_index + 1) % _tracks.length;
    await loadCurrent(autoplay: true);
  }

  Future<void> previous() async {
    if (_tracks.isEmpty) return;
    _index = (_index - 1 + _tracks.length) % _tracks.length;
    await loadCurrent(autoplay: true);
  }

  Future<void> playIndex(int i) async {
    if (i < 0 || i >= _tracks.length) return;
    _index = i;
    await loadCurrent(autoplay: true);
  }

  /// 拖动进度条（秒）。
  Future<void> seekTo(double seconds) async {
    final AudioPlayer? player = _player;
    if (player == null) return;
    final Duration target = Duration(milliseconds: (seconds * 1000).round());
    _position = target;
    notifyListeners();
    try {
      await player.seek(target);
    } catch (_) {
      // 在线流可能不支持跳转，忽略
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1).toDouble();
    final AudioPlayer? player = _ensurePlayer();
    if (player != null) {
      try {
        await player.setVolume(_volume);
      } catch (_) {
        _audioAvailable = false;
      }
    }
    notifyListeners();
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // 忽略
    }
    _playing = false;
    _position = Duration.zero;
    notifyListeners();
  }

  /// 启动时自动播放（由调用方根据「自动播放」开关决定是否调用）。
  Future<void> autoStart() async {
    if (_started) return;
    _started = true;
    if (_tracks.isEmpty) return;
    await loadCurrent(autoplay: true);
    notifyListeners();
  }

  void bindPlayerEvents() => _ensurePlayer();

  @override
  void dispose() {
    final AudioPlayer? player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
