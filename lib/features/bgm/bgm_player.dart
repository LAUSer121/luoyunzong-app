/// BGM 悬浮播放器：圆钮 + 展开面板 + 曲单弹窗。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/file_utils.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../state/bgm_controller.dart';

class BgmFab extends StatefulWidget {
  const BgmFab({super.key});

  @override
  State<BgmFab> createState() => _BgmFabState();
}

class _BgmFabState extends State<BgmFab> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final BgmController bgm = state.bgm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _panel(context, state, bgm),
                )
              : const SizedBox.shrink(),
        ),
        Tooltip(
          message: bgm.playing ? 'BGM 播放中：${bgm.title}' : 'BGM 音乐',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xF21B2030),
                  border: Border.all(
                    color: bgm.playing
                        ? AppColors.gold
                        : AppColors.goldDeep.withValues(alpha: 0.45),
                    width: bgm.playing ? 2 : 1,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.goldDeep.withValues(
                        alpha: bgm.playing ? 0.28 : 0.12,
                      ),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Icon(
                  bgm.playing
                      ? Icons.graphic_eq_rounded
                      : Icons.music_note_outlined,
                  color: bgm.playing ? AppColors.gold : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, AppState state, BgmController bgm) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            bgm.title,
            style: const TextStyle(color: AppColors.gold, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: '上一首',
                onPressed: bgm.tracks.isEmpty ? null : () => bgm.previous(),
                icon: const Icon(Icons.skip_previous_rounded),
                color: AppColors.goldDeep,
              ),
              IconButton(
                tooltip: bgm.playing ? '暂停' : '播放',
                onPressed: bgm.tracks.isEmpty ? null : () => bgm.toggle(),
                icon: Icon(
                  bgm.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 34,
                ),
                color: AppColors.gold,
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: bgm.tracks.isEmpty ? null : () => bgm.next(),
                icon: const Icon(Icons.skip_next_rounded),
                color: AppColors.goldDeep,
              ),
              IconButton(
                tooltip: '曲单',
                onPressed: () => _showPlaylist(context, state, bgm),
                icon: const Icon(Icons.queue_music_rounded),
                color: AppColors.goldDeep,
              ),
            ],
          ),
          SizedBox(
            width: 240,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.volume_up_outlined,
                  size: 16,
                  color: AppColors.textFaint,
                ),
                Expanded(
                  child: Slider(
                    value: bgm.volume,
                    onChanged: (double v) {
                      bgm.setVolume(v);
                      state.setBgmVolume(v);
                    },
                  ),
                ),
                Text(
                  '${(bgm.volume * 100).round()}',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (bgm.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 240,
                child: Text(
                  bgm.lastError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showPlaylist(
    BuildContext context,
    AppState state,
    BgmController bgm,
  ) async {
    final TextEditingController nameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) {
          final BgmController controller = ctx.watch<AppState>().bgm;
          return AlertDialog(
            title: const Text('BGM 曲单'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (controller.tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '曲单为空，请添加本地音乐',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: controller.tracks.length,
                        itemBuilder: (BuildContext c, int i) {
                          final BgmTrack t = controller.tracks[i];
                          final bool active = i == controller.index;
                          return ListTile(
                            dense: true,
                            selected: active,
                            title: Text(
                              t.name,
                              style: TextStyle(
                                color: active ? AppColors.gold : AppColors.text,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              t.missing
                                  ? '文件缺失'
                                  : (t.sessionOnly ? '本次会话有效' : '已保存到应用目录'),
                              style: TextStyle(
                                fontSize: 11,
                                color: t.missing
                                    ? AppColors.danger
                                    : AppColors.textFaint,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: '移出曲单',
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () async {
                                await state.removeBgmTrack(i);
                                setLocal(() {});
                              },
                            ),
                            onTap: () async {
                              await controller.playIndex(i);
                              setLocal(() {});
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final List<PickedBytes> files =
                                await pickMultipleBytes(
                                  extensions: <String>[
                                    'mp3',
                                    'wav',
                                    'ogg',
                                    'm4a',
                                    'flac',
                                    'aac',
                                  ],
                                  dialogTitle: '选择本地音乐',
                                );
                            if (files.isEmpty) return;
                            final String? msg = await state.addBgmFiles(
                              files
                                  .map(
                                    (PickedBytes f) =>
                                        (name: f.name, bytes: f.bytes),
                                  )
                                  .toList(),
                            );
                            if (ctx.mounted && msg != null) {
                              ScaffoldMessenger.of(ctx)
                                  .showSnackBar(SnackBar(content: Text(msg)));
                            }
                            setLocal(() {});
                          },
                          icon: const Icon(
                            Icons.library_music_outlined,
                            size: 16,
                          ),
                          label: const Text('添加本地音乐'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            hintText: '输入文件名（如 bgm1.mp3）',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final String name = nameController.text.trim();
                          if (name.isEmpty) return;
                          if (state.addBgmName(name)) {
                            await state.bgm.addByName(name);
                          }
                          nameController.clear();
                          setLocal(() {});
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.bgm.storageSupported
                        ? '提示：「添加本地音乐」会把文件复制到应用数据目录并随存档记录，下次启动仍可播放。'
                        : '提示：浏览器版本只能播放本次会话添加的音乐，桌面/手机版本可长期保存。',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
  }
}

/// 悬浮面板底：半透明玉牌。
class GlassPanel extends StatelessWidget {
  const GlassPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF21B2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
