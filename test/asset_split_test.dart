import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoyunzong/data/asset_split.dart';
import 'package:luoyunzong/domain/models.dart';

Uint8List _fakeJpeg(int bytes) {
  final Uint8List out = Uint8List(bytes);
  out[0] = 0xFF;
  out[1] = 0xD8;
  out[2] = 0xFF;
  return out;
}

String _dataUrl(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

void main() {
  group('资源拆分（云端只存引用）', () {
    test('大资源被替换成 asset: 引用，小资源保持内联', () {
      final Uint8List big = _fakeJpeg(80 * 1024);
      final Uint8List small = _fakeJpeg(4 * 1024);
      final Archive archive = Archive(
        memberList: <Member>[
          Member(
            name: '甲',
            role: '天骄',
            avatar: _dataUrl(small),
            portrait: _dataUrl(big),
          ),
          Member(name: '乙', role: '外门弟子', video: _dataUrl(big)),
        ],
        peakList: <Peak>[Peak(name: '落云峰', leader: '甲', avatar: _dataUrl(big))],
        background: BackgroundSetting(
          type: BgType.image,
          data: _dataUrl(big),
          autoOnline: true,
        ),
      );

      final AssetSplit split = splitAssets(archive);
      // 两个大图内容相同 → 去重后只有 1 个资源
      expect(split.assets.length, 1);
      expect(split.assets.single.bytes.length, big.length);
      expect(isAssetRef(archive.memberList[0].portrait), isFalse); // 原对象不被修改
      expect(isAssetRef(split.archive.memberList[0].portrait), isTrue);
      expect(isAssetRef(split.archive.memberList[1].video), isTrue);
      expect(isAssetRef(split.archive.peakList.single.avatar), isTrue);
      expect(isAssetRef(split.archive.background.data), isTrue);
      // 小头像不拆
      expect(split.archive.memberList[0].avatar!.startsWith('data:'), isTrue);
      expect(split.archive.background.autoOnline, isTrue);
    });

    test('还原后与原始内容一致', () {
      final Uint8List big = _fakeJpeg(80 * 1024);
      final Archive archive = Archive(
        memberList: <Member>[
          Member(
            name: '甲',
            role: '天骄',
            portrait: _dataUrl(big),
            video: _dataUrl(big),
          ),
        ],
        background: BackgroundSetting(
          type: BgType.image,
          data: _dataUrl(big),
          credit: 'x',
        ),
      );
      final AssetSplit split = splitAssets(archive);
      final Map<String, Uint8List> fetched = <String, Uint8List>{
        for (final AssetPayload a in split.assets) a.id: a.bytes,
      };
      final Archive restored = restoreAssets(split.archive, fetched);
      expect(restored.memberList.single.portrait, _dataUrl(big));
      expect(restored.memberList.single.video, _dataUrl(big));
      expect(restored.background.data, _dataUrl(big));
      expect(restored.background.credit, 'x');
    });

    test('引用到的 id 可枚举，缺失资源时保持引用不崩溃', () {
      final Uint8List big = _fakeJpeg(60 * 1024);
      final Archive archive = Archive(
        memberList: <Member>[
          Member(name: '甲', role: '天骄', portrait: _dataUrl(big)),
        ],
      );
      final AssetSplit split = splitAssets(archive);
      final Set<String> ids = referencedAssetIds(split.archive);
      expect(ids.length, 1);
      expect(ids.first, assetRefId(split.archive.memberList.single.portrait));

      // 服务端还没传上来时：保持引用，界面显示占位符
      final Archive partial = restoreAssets(
        split.archive,
        <String, Uint8List>{},
      );
      expect(isAssetRef(partial.memberList.single.portrait), isTrue);
    });

    test('相同内容得到相同 id（服务端按 id 去重）', () {
      final Uint8List a = _fakeJpeg(1000);
      final Uint8List b = Uint8List.fromList(a);
      expect(assetIdOf(a), assetIdOf(b));
      final Uint8List c = _fakeJpeg(1001);
      expect(assetIdOf(a), isNot(assetIdOf(c)));
    });

    test('data URL 解析出 MIME 与字节', () {
      final Uint8List bytes = _fakeJpeg(16);
      final decoded = decodeDataUrl(_dataUrl(bytes));
      expect(decoded, isNotNull);
      expect(decoded!.mime, 'image/jpeg');
      expect(decoded.bytes.length, 16);
      expect(decodeDataUrl('https://example.com/a.jpg'), isNull);
      expect(decodeDataUrl('asset:abc'), isNull);
    });
  });
}
