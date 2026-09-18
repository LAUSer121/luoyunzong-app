import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/data/netease_client.dart';
import 'package:luoyunzong/domain/models.dart';

void main() {
  group('网易云搜索结果解析', () {
    // 结构取自 cloudsearch/pc 的真实响应字段（ar / al / dt）
    final Map<String, Object?> response = <String, Object?>{
      'code': 200,
      'result': <String, Object?>{
        'songs': <Object?>[
          <String, Object?>{
            'id': 30352891,
            'name': '牵丝戏',
            'ar': <Object?>[
              <String, Object?>{'name': '银临'},
              <String, Object?>{'name': 'Aki阿杰'},
            ],
            'al': <String, Object?>{
              'name': '牵丝戏',
              'picUrl': 'http://p1.music.126.net/xx==/7725168696876736.jpg',
            },
            'dt': 239302,
          },
          <String, Object?>{'id': 0, 'name': '无效条目'},
          'invalid',
        ],
      },
    };

    test('提取歌名 / 歌手 / 封面 / 时长', () {
      final List<OnlineTrack> tracks = NeteaseClient.parseSearchResponse(
        response,
      );
      expect(tracks.length, 1);
      expect(tracks.single.id, '30352891');
      expect(tracks.single.name, '牵丝戏');
      expect(tracks.single.artist, '银临 / Aki阿杰');
      expect(tracks.single.cover, contains('music.126.net'));
      expect(tracks.single.durationMs, 239302);
      expect(tracks.single.subtitle, '银临 / Aki阿杰');
    });

    test('封面缩略图地址带裁剪参数', () {
      final OnlineTrack track = OnlineTrack(
        id: '1',
        name: 'x',
        cover: 'http://p1.music.126.net/a.jpg',
      );
      expect(
        NeteaseClient.coverUrl(track, size: 120),
        endsWith('?param=120y120'),
      );
      expect(NeteaseClient.coverUrl(OnlineTrack(id: '2', name: 'y')), '');
    });

    test('缺少 result 时返回空列表', () {
      expect(NeteaseClient.parseSearchResponse(<String, Object?>{}), isEmpty);
      expect(
        NeteaseClient.parseSearchResponse(<String, Object?>{'result': 'oops'}),
        isEmpty,
      );
    });

    test('预设关键词覆盖修仙题材', () {
      expect(NeteaseClient.presetKeywords, contains('仙侠'));
      expect(NeteaseClient.presetKeywords, contains('古风'));
    });
  });

  group('BGM 设置序列化', () {
    test('在线曲目与自动播放开关可往返', () {
      final BgmSetting setting = BgmSetting(
        volume: 0.42,
        customNames: <String>['bgm1.mp3'],
        onlineTracks: <OnlineTrack>[
          OnlineTrack(
            id: '30352891',
            name: '牵丝戏',
            artist: '银临',
            cover: 'c.jpg',
          ),
        ],
        index: 1,
        autoPlay: false,
      );
      final BgmSetting restored = BgmSetting.fromJson(setting.toJson());
      expect(restored.volume, 0.42);
      expect(restored.autoPlay, isFalse);
      expect(restored.customNames, <String>['bgm1.mp3']);
      expect(restored.onlineTracks.single.name, '牵丝戏');
      expect(restored.onlineTracks.single.artist, '银临');
    });

    test('旧存档没有 autoPlay 字段时默认开启', () {
      final BgmSetting restored = BgmSetting.fromJson(<String, Object?>{
        'volume': 0.5,
        'customNames': <Object?>['a.mp3'],
      });
      expect(restored.autoPlay, isTrue);
      expect(restored.onlineTracks, isEmpty);
    });

    test('存档整体往返保留在线曲单', () {
      final Archive archive = Archive(
        bgm: BgmSetting(
          onlineTracks: <OnlineTrack>[OnlineTrack(id: '1', name: '仙侠BGM')],
          autoPlay: false,
        ),
      );
      final Archive? parsed = ArchiveCodec.decode(
        ArchiveCodec.encodeJson(archive),
      );
      expect(parsed, isNotNull);
      expect(parsed!.bgm.onlineTracks.single.name, '仙侠BGM');
      expect(parsed.bgm.autoPlay, isFalse);
    });
  });
}
