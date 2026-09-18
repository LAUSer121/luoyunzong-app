/// 背景层：默认深空渐变 / 预设风格 / 自定义图片，外加灵光装饰。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../state/app_state.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BackgroundSetting bg = context.select<AppState, BackgroundSetting>(
      (AppState s) => s.archive.background,
    );
    final BgPreset? preset = bg.type == BgType.preset
        ? presetByKey(bg.key)
        : null;
    final Uint8List? imageBytes = bg.type == BgType.image && bg.data != null
        ? _decode(bg.data!)
        : null;

    final List<Color> colors = preset != null
        ? <Color>[Color(preset.beginColor), Color(preset.endColor)]
        : <Color>[const Color(0xFF0B1734), AppColors.backdrop];

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
          if (preset != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.5, -0.4),
                    radius: 1.1,
                    colors: <Color>[Color(preset.glowA), Colors.transparent],
                  ),
                ),
              ),
            ),
          if (preset != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.6, 0.55),
                    radius: 1.0,
                    colors: <Color>[Color(preset.glowB), Colors.transparent],
                  ),
                ),
              ),
            ),
          if (imageBytes != null)
            Positioned.fill(
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (imageBytes != null || preset != null)
            const Positioned.fill(child: ColoredBox(color: Color(0x66060C18))),
          // 光晕用 Align 定位：不参与 Stack 尺寸计算，避免把页面撑出横向滚动条。
          const Align(
            alignment: Alignment(-1.55, -1.55),
            child: _MagicGlow(size: 320),
          ),
          const Align(
            alignment: Alignment(1.45, 1.45),
            child: _MagicGlow(size: 380),
          ),
          child,
        ],
      ),
    );
  }

  static Uint8List? _decode(String dataUrl) {
    try {
      final int comma = dataUrl.indexOf(',');
      return base64Decode(comma == -1 ? dataUrl : dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}

class _MagicGlow extends StatelessWidget {
  const _MagicGlow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              AppColors.goldDeep.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
