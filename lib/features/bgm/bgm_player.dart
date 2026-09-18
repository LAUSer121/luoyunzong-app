/// BGM 悬浮播放器：封面、可拖动进度条、曲单、在线修仙电台（网易云）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/file_utils.dart';
import '../../core/theme.dart';
import '../../data/netease_client.dart';
import '../../domain/models.dart';
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
    final BgmTrack? current = bgm.current;
    final String? cover = current?.cover;
    final String subtitle = current?.subtitle ?? '点曲单或在线电台添加音乐';

    return GlassPanel(
      child: SizedBox(
        width: 288,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                CoverArt(url: cover, size: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        bgm.resolving ? '正在解析播放地址…' : bgm.title,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _progress(bgm),
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
                  onPressed: () => _showPlaylistDialog(context, state),
                  icon: const Icon(Icons.queue_music_rounded),
                  color: AppColors.goldDeep,
                ),
                IconButton(
                  tooltip: '在线修仙电台',
                  onPressed: () => showRadioDialog(context, state),
                  icon: const Icon(Icons.travel_explore_rounded),
                  color: AppColors.gold,
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: bgm.resolving
                    ? null
                    : () async {
                        final String? msg = await state.bgm.autoFillXianxia();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg ?? '已切换仙侠电台')),
                        );
                      },
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(bgm.resolving ? '正在挑选仙侠曲目…' : '一键仙侠电台'),
              ),
            ),
            const SizedBox(height: 6),
            Row(
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: state.bgmAutoPlay,
              onChanged: state.setBgmAutoPlay,
              title: const Text('启动后自动播放', style: TextStyle(fontSize: 12)),
              subtitle: const Text(
                '关闭后进入应用不自动播放 BGM',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
            if (bgm.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  bgm.lastError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _progress(BgmController bgm) {
    final double max = bgm.duration.inMilliseconds == 0
        ? 1
        : bgm.duration.inMilliseconds.toDouble();
    final double value = bgm.duration.inMilliseconds == 0
        ? 0
        : bgm.position.inMilliseconds
              .clamp(0, bgm.duration.inMilliseconds)
              .toDouble();
    return Row(
      children: <Widget>[
        Text(
          formatDuration(bgm.position),
          style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              min: 0,
              max: max,
              value: value,
              onChanged: (double v) => bgm.seekTo(v / 1000),
            ),
          ),
        ),
        Text(
          formatDuration(bgm.duration),
          style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 曲单
  // ------------------------------------------------------------------
  Future<void> _showPlaylistDialog(BuildContext context, AppState state) async {
    final TextEditingController nameController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setLocal) {
          final BgmController controller = ctx.watch<AppState>().bgm;
          return AlertDialog(
            title: const Text('BGM 曲单'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (controller.tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '曲单为空：可添加本地音乐，或用「在线修仙电台」搜索',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: controller.tracks.length,
                        itemBuilder: (BuildContext c, int i) {
                          final BgmTrack t = controller.tracks[i];
                          final bool active = i == controller.index;
                          return ListTile(
                            dense: true,
                            selected: active,
                            leading: CoverArt(url: t.cover, size: 36),
                            title: Text(
                              t.name,
                              style: TextStyle(
                                color: active ? AppColors.gold : AppColors.text,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              t.subtitle,
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
                                final OnlineTrack? online = t.online;
                                await controller.removeTrack(i);
                                if (online != null) {
                                  state.removeOnlineTrack(online.id);
                                }
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
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
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await showRadioDialog(context, state);
                        },
                        icon: const Icon(
                          Icons.travel_explore_rounded,
                          size: 16,
                        ),
                        label: const Text('在线修仙电台'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                        ? '提示：本地音乐会复制到应用数据目录并随存档记录。'
                        : '提示：浏览器版本只能播放本次会话添加的音乐。',
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
///
/// 必须是 Material：面板里有 SwitchListTile / InkWell，
/// 缺少 Material 祖先时它们的背景与涟漪会画在错误的表面上（表现为一块白窗）。
class GlassPanel extends StatelessWidget {
  const GlassPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF21B2030),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
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
      ),
    );
  }
}

/// 封面：网络封面 + 音符占位（本地曲目没有封面）。
class CoverArt extends StatelessWidget {
  const CoverArt({required this.url, this.size = 46, super.key});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String src = url ?? '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.goldDeep.withValues(alpha: 0.5)),
        color: const Color(0x33101A2E),
      ),
      clipBehavior: Clip.antiAlias,
      child: src.isEmpty
          ? Icon(Icons.music_note, size: size * 0.5, color: AppColors.goldDeep)
          : Image.network(
              src,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.music_note,
                size: size * 0.5,
                color: AppColors.goldDeep,
              ),
            ),
    );
  }
}

/// 秒数 → `m:ss`。
String formatDuration(Duration d) {
  final int m = d.inMinutes;
  final int s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 在线修仙电台：搜索网易云歌曲，可试听或加入曲单。
Future<void> showRadioDialog(BuildContext context, AppState state) async {
  final TextEditingController keyword = TextEditingController(
    text: NeteaseClient.presetKeywords.first,
  );
  List<OnlineTrack> results = <OnlineTrack>[];
  bool loading = false;
  String? error;
  bool searched = false;

  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, void Function(void Function()) setLocal) {
        Future<void> runSearch(String kw) async {
          setLocal(() {
            loading = true;
            error = null;
          });
          try {
            final List<OnlineTrack> found = await state.netease.search(kw);
            setLocal(() {
              results = found;
              searched = true;
              loading = false;
            });
          } on NeteaseException catch (e) {
            setLocal(() {
              error = e.message;
              loading = false;
              searched = true;
            });
          } catch (e) {
            setLocal(() {
              error = '搜索失败：$e';
              loading = false;
              searched = true;
            });
          }
        }

        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(
                Icons.travel_explore_rounded,
                size: 20,
                color: AppColors.gold,
              ),
              SizedBox(width: 8),
              Text('在线修仙电台'),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NeteaseClient.presetKeywords
                      .map(
                        (String k) => ActionChip(
                          label: Text(k, style: const TextStyle(fontSize: 12)),
                          onPressed: loading
                              ? null
                              : () {
                                  keyword.text = k;
                                  runSearch(k);
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: keyword,
                        decoration: const InputDecoration(
                          labelText: '搜索关键词',
                          hintText: '如：仙侠 / 古风 / 洞箫',
                          isDense: true,
                        ),
                        onSubmitted: (String v) {
                          if (!loading) runSearch(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: loading ? null : () => runSearch(keyword.text),
                      child: Text(loading ? '搜索中…' : '搜索'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: loading
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              final String? msg = await state.bgm
                                  .autoFillXianxia();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(msg ?? '已切换仙侠电台')),
                              );
                            },
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('一键挑选'),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                if (!state.netease.useProxy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '提示：桌面/手机版可直接搜索；浏览器版受跨域限制，可在「设置 → 在线电台代理」'
                      '填写自建 NeteaseCloudMusicApi 地址后重试。',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (results.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (BuildContext c, int i) {
                        final OnlineTrack t = results[i];
                        return ListTile(
                          dense: true,
                          leading: CoverArt(
                            url: NeteaseClient.coverUrl(t, size: 80),
                            size: 40,
                          ),
                          title: Text(
                            t.name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t.subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textFaint,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                tooltip: '试听',
                                icon: const Icon(
                                  Icons.play_circle_outline,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  await state.bgm.playOnlinePreview(t);
                                },
                              ),
                              IconButton(
                                tooltip: '加入曲单',
                                icon: const Icon(Icons.playlist_add, size: 20),
                                onPressed: () {
                                  state.addOnlineTrack(t);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('已加入曲单：${t.name}')),
                                  );
                                  setLocal(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  )
                else if (searched && error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '没有搜到结果，换个关键词试试',
                      style: TextStyle(color: AppColors.textFaint),
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
  keyword.dispose();
}
