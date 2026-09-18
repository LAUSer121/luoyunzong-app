/// 桌面 / 移动端视频舞台：media_kit 播放（base64 落盘为临时文件后播放）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';

bool _mediaKitReady = false;

void _ensureMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

/// 播放 base64 视频；播放结束回调 [onFinished]，由弹窗切回立绘。
class VideoStage extends StatefulWidget {
  const VideoStage({
    required this.dataUrl,
    this.onFinished,
    this.autoPlay = true,
    super.key,
  });

  final String dataUrl;
  final VoidCallback? onFinished;
  final bool autoPlay;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _completedSub;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ensureMediaKit();
    _player = Player();
    _controller = VideoController(_player);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final Uint8List? bytes = _decode(widget.dataUrl);
      if (bytes == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final Directory dir = await getTemporaryDirectory();
      final File file = File(
        '${dir.path}${Platform.pathSeparator}luoyunzong_video_${widget.dataUrl.length}.mp4',
      );
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      await _player.open(
        Media(Uri.file(file.path).toString()),
        play: widget.autoPlay,
      );
      _completedSub = _player.stream.completed.listen((bool done) {
        if (done) widget.onFinished?.call();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_completedSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const ColoredBox(
        color: Color(0x66101A2E),
        child: Center(
          child: Text(
            '视频解码失败，可尝试重新上传',
            style: TextStyle(color: AppColors.textFaint),
          ),
        ),
      );
    }
    return Video(
      controller: _controller,
      controls: AdaptiveVideoControls,
      fill: const Color(0x66101A2E),
    );
  }
}

Uint8List? _decode(String dataUrl) {
  try {
    final int comma = dataUrl.indexOf(',');
    return base64Decode(comma == -1 ? dataUrl : dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// 读取视频时长（秒）；失败返回 `null`。用于上传前的 25 秒限制校验。
Future<double?> probeVideoDurationSeconds(Uint8List bytes) async {
  _ensureMediaKit();
  final Player player = Player();
  try {
    final Directory dir = await getTemporaryDirectory();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}luoyunzong_probe_${bytes.length}.mp4',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    await player.open(Media(Uri.file(file.path).toString()), play: false);
    final Duration duration = await player.stream.duration
        .firstWhere((Duration d) => d > Duration.zero)
        .timeout(const Duration(seconds: 8), onTimeout: () => Duration.zero);
    return duration.inMilliseconds / 1000.0;
  } catch (_) {
    return null;
  } finally {
    unawaited(player.dispose());
  }
}
