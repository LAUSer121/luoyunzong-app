import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/archive_codec.dart';
import 'package:luoyunzong/data/wallpaper_client.dart';
import 'package:luoyunzong/domain/models.dart';

void main() {
  group('在线背景设置', () {
    test('credit 与自动获取开关可往返', () {
      final BackgroundSetting bg = BackgroundSetting(
        type: BgType.image,
        data: 'data:image/jpeg;base64,AAAA',
        credit: '图片来自 必应图片搜索 · 1920x1080',
        autoOnline: true,
      );
      final BackgroundSetting restored = BackgroundSetting.fromJson(
        bg.toJson(),
      );
      expect(restored.type, BgType.image);
      expect(restored.data, 'data:image/jpeg;base64,AAAA');
      expect(restored.credit, contains('必应图片搜索'));
      expect(restored.autoOnline, isTrue);
      expect(restored.label, '在线背景');
    });

    test('旧存档缺字段时默认关闭自动获取', () {
      final BackgroundSetting restored = BackgroundSetting.fromJson(
        <String, Object?>{'type': 'preset', 'key': 'jade'},
      );
      expect(restored.autoOnline, isFalse);
      expect(restored.credit, '');
      expect(restored.label, '翠微青山');
    });

    test('切换预设/默认背景时保留自动获取开关', () {
      final BackgroundSetting online = BackgroundSetting(autoOnline: true);
      final BackgroundSetting preset = online.copyWith(
        type: BgType.preset,
        key: 'night',
        credit: '',
      );
      expect(preset.autoOnline, isTrue);
      expect(preset.key, 'night');
      final BackgroundSetting cleared = preset.copyWith(
        clearImage: true,
        credit: '',
      );
      expect(cleared.autoOnline, isTrue);
    });

    test('整包存档往返保留在线背景信息', () {
      final Archive archive = Archive(
        background: BackgroundSetting(
          type: BgType.image,
          data: 'data:image/jpeg;base64,BBBB',
          credit: '图片来自 Wallhaven · 作者 tester · 1920x1080',
          autoOnline: true,
        ),
      );
      final Archive? parsed = ArchiveCodec.decode(
        ArchiveCodec.encodeJson(archive),
      );
      expect(parsed, isNotNull);
      expect(parsed!.background.autoOnline, isTrue);
      expect(parsed.background.credit, contains('Wallhaven'));
      expect(parsed.background.data, contains('BBBB'));
    });
  });

  group('在线背景图源配置', () {
    test('提供中文检索词与英文标签', () {
      expect(WallpaperClient.presetQueries, contains('仙侠 壁纸'));
      expect(WallpaperClient.presetQueries, contains('水墨山水 壁纸'));
      expect(WallpaperClient.presetTags, contains('chinese landscape'));
    });

    test('署名文案包含来源与分辨率', () {
      const OnlineWallpaper w = OnlineWallpaper(
        imageUrl: 'https://example.com/a.jpg',
        source: '必应每日壁纸',
        author: '某地风景 (© Someone)',
        resolution: '1920x1080',
      );
      expect(w.credit, contains('必应每日壁纸'));
      expect(
        w.credit,
        contains('SomeOne'.toLowerCase() == 'someone' ? 'Some' : 'Some'),
      );
      expect(w.credit, contains('1920x1080'));
    });
  });
}
