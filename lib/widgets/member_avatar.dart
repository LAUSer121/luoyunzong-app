/// 头像组件：点击查看立绘与动态视频。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/models.dart';

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    required this.member,
    this.size = 44,
    this.onTap,
    this.showMediaBadges = true,
    super.key,
  });

  final Member member;
  final double size;
  final VoidCallback? onTap;
  final bool showMediaBadges;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _decode(member.avatar);
    final bool hasPortrait =
        member.portrait != null && member.portrait!.isNotEmpty;
    final bool hasVideo = member.video != null && member.video!.isNotEmpty;

    return Tooltip(
      message: hasPortrait || hasVideo ? '点击查看立绘 / 动态视频' : '点击查看人物详情',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasPortrait
                      ? AppColors.gold
                      : AppColors.goldDeep.withValues(alpha: 0.4),
                ),
                color: const Color(0x33101A2E),
                boxShadow: hasPortrait
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.22),
                          blurRadius: 10,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            // 右下角用图标标出「有立绘 / 有动态视频」，不再写文字
            if (showMediaBadges && (hasVideo || hasPortrait))
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0B1226),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.goldDeep.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (hasPortrait)
                        const Icon(
                          Icons.image_rounded,
                          size: 11,
                          color: AppColors.goldDeep,
                        ),
                      if (hasPortrait && hasVideo) const SizedBox(width: 2),
                      if (hasVideo)
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 11,
                          color: Color(0xFF7DB8FF),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: Text(
      '侠',
      style: TextStyle(color: AppColors.goldDeep, fontSize: size * 0.44),
    ),
  );

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      final int comma = dataUrl.indexOf(',');
      return base64Decode(comma == -1 ? dataUrl : dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}

/// 山峰头像（同样的占位逻辑，占位字为「峰」）。
class PeakAvatar extends StatelessWidget {
  const PeakAvatar({required this.avatar, this.size = 52, super.key});

  final String? avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = MemberAvatar._decode(avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.goldDeep.withValues(alpha: 0.5)),
        color: const Color(0x33101A2E),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
          : Center(
              child: Text(
                '峰',
                style: TextStyle(
                  color: AppColors.goldDeep,
                  fontSize: size * 0.4,
                ),
              ),
            ),
    );
  }
}
