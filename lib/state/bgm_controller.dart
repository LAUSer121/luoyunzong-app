/// BGM 播放控制器：曲单来自存档（长期曲目）+ 本次会话曲目。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../data/bgm_store.dart';

class BgmTrack {
  BgmTrack({
    required this.name,
    this.path,
    this.bytes,
    this.sessionOnly = false,
  });

  final String name;
  String? path;

  /// 会话曲目（Web 端或有临时文件时直接用内存播放）。
  Uint8List? bytes;
  final bool sessionOnly;
  bool missing = false;
}

class BgmController extends ChangeNotifier {
  BgmController();

  final AudioPlayer _player = AudioPlayer();

  final List<BgmTrack> _tracks = <BgmTrack>[];
  int _index = 0;
  double _volume = 0.6;
  bool _playing = false;
  bool _started = false;
  String? _lastError;

  List<BgmTrack> get tracks => List<BgmTrack>.unmodifiable(_tracks);
  int get index => _index;
  double get volume => _volume;
  bool get playing => _playing;
  String? get lastError => _lastError;
  BgmTrack? get current =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;
  String get title => current?.name ?? '未选择音乐';
  bool get storageSupported => bgmStorageSupported;

  /// 依据存档重建曲单（存档里保存的是「长期曲目」文件名）。
  ///
  /// 会话曲目（用户本次导入、无法落盘的音乐）会被保留，排在长期曲目之后。
  Future<void> syncFromArchive(Archive archive) async {
    final List<BgmTrack> sessionTracks = _tracks
        .where((BgmTrack t) => t.sessionOnly)
        .toList();
    _tracks
      ..clear()
      ..addAll(
        archive.bgm.customNames.map((String name) => BgmTrack(name: name)),
      )
      ..addAll(sessionTracks);

    _volume = archive.bgm.volume;
    await _player.setVolume(_volume);

    for (final BgmTrack t in _tracks) {
      if (!t.sessionOnly) {
        t.path = await audioFilePath(t.name);
        t.missing = t.path == null;
      }
    }
    _index = _tracks.isEmpty
        ? 0
        : archive.bgm.index.clamp(0, _tracks.length - 1);
    notifyListeners();
  }

  /// 添加本地音乐文件（复制到应用数据目录，随存档长期保留；Web 端为会话曲目）。
  Future<String?> addFiles(List<({String name, Uint8List bytes})> files) async {
    if (files.isEmpty) return '没有可用的音频文件';
    final List<String> addedNames = <String>[];
    for (final ({String name, Uint8List bytes}) f in files) {
      final String? path = await storeAudioFile(f.name, f.bytes);
      if (path != null) {
        _tracks.add(BgmTrack(name: f.name, path: path));
        addedNames.add(f.name);
      } else {
        _tracks.add(BgmTrack(name: f.name, bytes: f.bytes, sessionOnly: true));
        addedNames.add(f.name);
      }
    }
    if (_player.source == null && _tracks.isNotEmpty) {
      _index = _tracks.length - 1;
    }
    notifyListeners();
    return '已添加 ${addedNames.length} 首音乐';
  }

  /// 由曲单列表（长期曲目）同步一次，返回新增曲目名。
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

  Future<void> removeTrack(int i) async {
    if (i < 0 || i >= _tracks.length) return;
    final BgmTrack t = _tracks[i];
    if (!t.sessionOnly) await deleteAudioFile(t.name);
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

  Future<void> loadCurrent({bool autoplay = true}) async {
    final BgmTrack? t = current;
    if (t == null) {
      notifyListeners();
      return;
    }
    try {
      if (t.path != null) {
        await _player.play(DeviceFileSource(t.path!), volume: _volume);
      } else if (t.bytes != null) {
        await _player.play(BytesSource(t.bytes!), volume: _volume);
      } else {
        t.missing = true;
        _lastError = '未找到音乐文件：${t.name}';
        notifyListeners();
        return;
      }
      _playing = autoplay;
      _lastError = null;
    } catch (e) {
      _playing = false;
      _lastError = '播放失败：$e';
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_tracks.isEmpty) return;
    if (_playing) {
      await _player.pause();
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

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1).toDouble();
    await _player.setVolume(_volume);
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _playing = false;
    notifyListeners();
  }

  /// 首次启动自动播放（浏览器可能拦截，失败时静默）。
  Future<void> autoStart() async {
    if (_started) return;
    _started = true;
    if (_tracks.isEmpty) return;
    await loadCurrent(autoplay: true);
    if (!_playing) _playing = false;
    notifyListeners();
  }

  void bindPlayerEvents() {
    _player.onPlayerComplete.listen((_) => unawaited(next(auto: true)));
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }
}
