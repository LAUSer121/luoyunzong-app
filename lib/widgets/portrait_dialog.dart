/// 人物详情弹窗：立绘 ⇄ 动态视频，支持上传 / 移除（需解锁编辑）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/file_utils.dart';
import '../core/image_utils.dart';
import '../core/theme.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'badges.dart';
import 'member_avatar.dart';
import 'video_stage.dart';

Future<void> showPortraitDialog(BuildContext context, String memberName) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _PortraitDialog(memberName: memberName),
  );
}

class _PortraitDialog extends StatefulWidget {
  const _PortraitDialog({required this.memberName});

  final String memberName;

  @override
  State<_PortraitDialog> createState() => _PortraitDialogState();
}

class _PortraitDialogState extends State<_PortraitDialog> {
  bool _showVideo = false;
  bool _busy = false;

  Future<void> _pickPortrait(AppState state) async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      dialogTitle: '选择立绘图片',
    );
    if (picked == null) return;
    final String? data = compressImageToDataUrl(
      picked.bytes,
      maxWidth: 720,
      quality: 90,
    );
    if (data == null) {
      _toast('图片读取失败');
      return;
    }
    state.setPortrait(widget.memberName, data);
    _toast('立绘已更新');
  }

  Future<void> _pickVideo(AppState state) async {
    final PickedBytes? picked = await pickBytes(
      extensions: <String>['mp4', 'webm', 'mov', 'm4v'],
      dialogTitle: '选择动态视频',
    );
    if (picked == null) return;
    if (picked.bytes.length > kVideoMaxBytes) {
      _toast('视频超过 20MB，请压缩后再上传（建议 480p、25 秒内）');
      return;
    }
    setState(() => _busy = true);
    final double? seconds = await probeVideoDurationSeconds(picked.bytes);
    setState(() => _busy = false);
    if (seconds != null && seconds > kVideoMaxSeconds) {
      _toast('视频时长 ${seconds.toStringAsFixed(1)} 秒，超过 $kVideoMaxSeconds 秒上限');
      return;
    }
    state.setVideo(
      widget.memberName,
      'data:video/mp4;base64,${base64Encode(picked.bytes)}',
    );
    setState(() => _showVideo = true);
    _toast('动态视频已更新，随存档一起保存');
  }

  Future<void> _exportVideo(String dataUrl) async {
    final Uint8List? bytes = dataUrlToBytes(dataUrl);
    if (bytes == null) {
      _toast('视频数据已损坏');
      return;
    }
    final String? path = await saveBinaryFile(
      fileName: '${widget.memberName}-动态视频.mp4',
      bytes: bytes,
    );
    if (path != null) _toast('已导出：$path');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Member? m = state.archive.memberByName(widget.memberName);
    if (m == null) {
      return AlertDialog(
        title: const Text('人物详情'),
        content: const Text('该成员已离宗'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    final bool unlocked = state.unlocked;
    final bool hasPortrait = m.portrait != null && m.portrait!.isNotEmpty;
    final bool hasVideo = m.video != null && m.video!.isNotEmpty;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      title: Row(
        children: <Widget>[
          MemberAvatar(member: m, size: 38, showMediaBadges: false),
          const SizedBox(width: 12),
          Expanded(child: Text(m.name)),
          RoleBadge(m.role, dense: true),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  RealmBadge.of(m),
                  const SizedBox(width: 8),
                  SubRoleChips(member: m),
                ],
              ),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x66101A2E),
                      border: Border.all(color: AppColors.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _stage(m, hasPortrait, hasVideo),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasVideo
                    ? (_showVideo ? '正在播放动态视频，播完自动回到立绘' : '点击立绘播放动态视频')
                    : '暂无动态视频，上传后将随存档保存',
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            if (unlocked)
              OutlinedButton.icon(
                onPressed: () => _pickPortrait(state),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('上传立绘'),
              ),
            if (unlocked && hasPortrait)
              OutlinedButton(
                onPressed: () {
                  state.setPortrait(widget.memberName, null);
                  _toast('立绘已移除');
                },
                child: const Text('移除立绘'),
              ),
            if (unlocked)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickVideo(state),
                icon: const Icon(Icons.movie_outlined, size: 18),
                label: Text(_busy ? '校验中…' : '上传视频'),
              ),
            if (hasVideo)
              OutlinedButton.icon(
                onPressed: () => _exportVideo(m.video!),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('导出视频'),
              ),
            if (unlocked && hasVideo)
              OutlinedButton(
                onPressed: () {
                  state.setVideo(widget.memberName, null);
                  setState(() => _showVideo = false);
                  _toast('动态视频已移除');
                },
                child: const Text('移除视频'),
              ),
          ],
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _stage(Member m, bool hasPortrait, bool hasVideo) {
    if (_showVideo && hasVideo) {
      return VideoStage(
        dataUrl: m.video!,
        onFinished: () {
          if (mounted) setState(() => _showVideo = false);
        },
      );
    }
    final Uint8List? bytes = hasPortrait ? dataUrlToBytes(m.portrait!) : null;
    if (bytes == null) {
      return const Center(
        child: Text(
          '侠',
          style: TextStyle(color: AppColors.goldDeep, fontSize: 64),
        ),
      );
    }
    return GestureDetector(
      onTap: hasVideo ? () => setState(() => _showVideo = true) : null,
      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}
