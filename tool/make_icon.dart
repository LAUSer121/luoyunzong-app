// 生成「修仙风」应用图标（仙山 + 灵珠 + 鎏金圆环 + 云海）。
//
// 用法：dart run tool/make_icon.dart [输出目录，默认 assets/icon]
// 产物：icon.png（1024，供 flutter_launcher_icons 各平台派生）、icon_512.png、icon_256.png

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int kSize = 1024;

void main(List<String> args) {
  final String outDir = args.isNotEmpty ? args[0] : 'assets/icon';
  Directory(outDir).createSync(recursive: true);

  final img.Image canvas = img.Image(
    width: kSize,
    height: kSize,
    numChannels: 4,
  );
  _paintBackground(canvas);
  _paintStars(canvas);
  _paintRings(canvas);
  _paintOrb(canvas);
  _paintMountains(canvas);
  _paintClouds(canvas);

  final String mainPath = '$outDir/icon.png';
  File(mainPath).writeAsBytesSync(img.encodePng(canvas));
  for (final int size in <int>[512, 256, 192]) {
    final img.Image resized = img.copyResize(
      canvas,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    File('$outDir/icon_$size.png').writeAsBytesSync(img.encodePng(resized));
  }
  stdout.writeln('[icon] 生成完成：$mainPath（$kSize×$kSize）');
}

/// 深空底 + 中心灵光。
void _paintBackground(img.Image image) {
  const double cx = kSize / 2;
  const double cy = kSize / 2;
  final img.Color center = img.ColorRgb8(0x14, 0x22, 0x40);
  final img.Color edge = img.ColorRgb8(0x07, 0x0D, 0x1C);
  for (int y = 0; y < kSize; y++) {
    for (int x = 0; x < kSize; x++) {
      final double d =
          math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2)) / (kSize * 0.62);
      final double t = d.clamp(0.0, 1.0);
      final int r = (center.r + (edge.r - center.r) * t).round();
      final int g = (center.g + (edge.g - center.g) * t).round();
      final int b = (center.b + (edge.b - center.b) * t).round();
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

/// 星点（极淡，避免小尺寸下变成糊点）。
void _paintStars(img.Image image) {
  final math.Random rnd = math.Random(20260919);
  for (int i = 0; i < 90; i++) {
    final int x = rnd.nextInt(kSize);
    final int y = rnd.nextInt(kSize ~/ 2);
    final double dist = math.sqrt(
      math.pow(x - kSize / 2, 2) + math.pow(y - kSize / 2, 2),
    );
    if (dist < 330) continue; // 中心留给山与珠
    img.fillCircle(
      image,
      x: x,
      y: y,
      radius: rnd.nextInt(3) + 1,
      color: img.ColorRgba8(0xF7, 0xE2, 0xA8, rnd.nextInt(70) + 30),
    );
  }
}

/// 双鎏金圆环。
void _paintRings(img.Image image) {
  const int cx = kSize ~/ 2;
  const int cy = kSize ~/ 2;
  _arc(
    image,
    cx,
    cy,
    452,
    0,
    math.pi * 2,
    img.ColorRgba8(0xD4, 0xB8, 0x86, 255),
    15,
  );
  _arc(
    image,
    cx,
    cy,
    418,
    0,
    math.pi * 2,
    img.ColorRgba8(0xF7, 0xE2, 0xA8, 150),
    5,
  );
  // 四方位云纹短弧（内外各一圈）
  for (int i = 0; i < 4; i++) {
    final double a0 = math.pi / 2 * i - 0.22;
    final double a1 = a0 + 0.44;
    _arc(image, cx, cy, 380, a0, a1, img.ColorRgba8(0xF7, 0xE2, 0xA8, 210), 7);
    _arc(image, cx, cy, 496, a0, a1, img.ColorRgba8(0xD4, 0xB8, 0x86, 200), 7);
  }
}

void _arc(
  img.Image image,
  int cx,
  int cy,
  double radius,
  double from,
  double to,
  img.Color color,
  int thickness,
) {
  for (double a = from; a <= to; a += 0.004) {
    final int x = (cx + math.cos(a) * radius).round();
    final int y = (cy + math.sin(a) * radius).round();
    img.fillCircle(image, x: x, y: y, radius: thickness ~/ 2, color: color);
  }
}

/// 灵珠：金色光晕 + 实心珠。
void _paintOrb(img.Image image) {
  const int x = kSize ~/ 2;
  const int y = 262;
  for (int r = 120; r > 44; r -= 6) {
    final double t = (120 - r) / 76;
    img.fillCircle(
      image,
      x: x,
      y: y,
      radius: r,
      color: img.ColorRgba8(0xF7, 0xE2, 0xA8, (14 * (1 - t) + 3).round()),
    );
  }
  img.fillCircle(
    image,
    x: x,
    y: y,
    radius: 46,
    color: img.ColorRgb8(0xFF, 0xE9, 0xA8),
  );
  img.fillCircle(
    image,
    x: x,
    y: y,
    radius: 34,
    color: img.ColorRgb8(0xFF, 0xD7, 0x66),
  );
  img.fillCircle(
    image,
    x: x - 12,
    y: y - 12,
    radius: 10,
    color: img.ColorRgb8(0xFF, 0xFA, 0xE0),
  );
}

/// 仙山：主峰 + 两翼，玉色山体 + 金顶。
void _paintMountains(img.Image image) {
  const int baseY = 742;
  final img.Color jadeDark = img.ColorRgb8(0x1B, 0x4A, 0x3C);
  final img.Color jade = img.ColorRgb8(0x2E, 0x6B, 0x55);
  final img.Color jadeLight = img.ColorRgb8(0x4E, 0x96, 0x76);

  // 两翼（先画，位于主峰之后）
  _peak(image, 316, 470, 168, baseY, jade, jadeDark);
  _peak(image, 716, 470, 168, baseY, jade, jadeDark);
  // 主峰
  _peak(image, 512, 372, 210, baseY, jadeLight, jade);

  // 金顶
  _cap(image, 512, 372, 210, baseY, img.ColorRgb8(0xF7, 0xE2, 0xA8));
  _cap(image, 316, 470, 168, baseY, img.ColorRgba8(0xF7, 0xE2, 0xA8, 190));
  _cap(image, 716, 470, 168, baseY, img.ColorRgba8(0xF7, 0xE2, 0xA8, 190));
}

void _peak(
  img.Image image,
  int apexX,
  int apexY,
  int halfWidth,
  int baseY,
  img.Color body,
  img.Color shade,
) {
  final List<img.Point> vertices = <img.Point>[
    img.Point(apexX, apexY),
    img.Point(apexX + halfWidth, baseY),
    img.Point(apexX - halfWidth, baseY),
  ];
  img.fillPolygon(image, vertices: vertices, color: shade);
  // 左半受光
  final List<img.Point> lit = <img.Point>[
    img.Point(apexX, apexY),
    img.Point(apexX - halfWidth ~/ 6, baseY),
    img.Point(apexX - halfWidth, baseY),
  ];
  img.fillPolygon(image, vertices: lit, color: body);
}

/// 山顶金边（雪顶意象）。
void _cap(
  img.Image image,
  int apexX,
  int apexY,
  int halfWidth,
  int baseY,
  img.Color color,
) {
  const double capRatio = 0.22;
  final int capY = (apexY + (baseY - apexY) * capRatio).round();
  final int capHalf = (halfWidth * capRatio).round();
  img.fillPolygon(
    image,
    vertices: <img.Point>[
      img.Point(apexX, apexY),
      img.Point(apexX + capHalf, capY),
      img.Point(apexX - capHalf, capY),
    ],
    color: color,
  );
}

/// 云海：山脚几层柔白云带。
void _paintClouds(img.Image image) {
  const int baseY = 748;
  final List<List<int>> bands = <List<int>>[
    <int>[364, baseY - 16, 214, 30, 150],
    <int>[660, baseY - 12, 226, 28, 140],
    <int>[512, baseY + 26, 320, 34, 170],
    <int>[286, baseY + 46, 150, 24, 110],
    <int>[740, baseY + 50, 150, 24, 110],
  ];
  for (final List<int> b in bands) {
    _fillEllipse(
      image,
      b[0],
      b[1],
      b[2],
      b[3],
      img.ColorRgba8(0xF7, 0xEF, 0xDC, b[4]),
    );
  }
}

/// 椭圆填充（image 4.x 没有 fillEllipse，这里自己实现带 alpha 混合的版本）。
void _fillEllipse(
  img.Image image,
  int cx,
  int cy,
  int rx,
  int ry,
  img.Color color,
) {
  final double a = color.a / 255.0;
  for (int y = cy - ry; y <= cy + ry; y++) {
    if (y < 0 || y >= image.height) continue;
    for (int x = cx - rx; x <= cx + rx; x++) {
      if (x < 0 || x >= image.width) continue;
      final double dx = (x - cx) / rx;
      final double dy = (y - cy) / ry;
      if (dx * dx + dy * dy > 1) continue;
      final img.Pixel base = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        (base.r * (1 - a) + color.r * a).round(),
        (base.g * (1 - a) + color.g * a).round(),
        (base.b * (1 - a) + color.b * a).round(),
        255,
      );
    }
  }
}
