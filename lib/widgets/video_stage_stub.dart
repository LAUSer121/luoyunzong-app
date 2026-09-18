/// Web 端视频舞台：浏览器内不做内嵌解码，提示用「导出视频」后本地播放。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';

class VideoStage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x66101A2E),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '浏览器版本暂不支持内嵌播放动态视频，\n可点下方「导出视频」后用本地播放器观看。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textFaint, height: 1.7),
          ),
        ),
      ),
    );
  }
}

/// Web 端无法读取时长，返回 `null`（跳过 25 秒校验）。
Future<double?> probeVideoDurationSeconds(Uint8List bytes) async => null;
