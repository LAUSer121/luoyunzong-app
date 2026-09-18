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
            if (showMediaBadges && hasVideo)
              Positioned(
                right: -3,
                top: -3,
                child: _dot(Icons.play_arrow_rounded, const Color(0xFF7DB8FF)),
              ),
            if (showMediaBadges && hasPortrait)
              Positioned(
                left: -3,
                top: -3,
                child: _dot(Icons.image_outlined, AppColors.goldDeep),
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

  Widget _dot(IconData icon, Color color) => Container(
    width: 15,
    height: 15,
    decoration: BoxDecoration(
      color: const Color(0xF21B2030),
      shape: BoxShape.circle,
      border: Border.all(color: color),
    ),
    child: Icon(icon, size: 10, color: color),
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
