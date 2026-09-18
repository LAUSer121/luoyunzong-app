/// 全局常量：职务、境界、任务档次、默认值。
///
/// 数值与旧版 `luoyunzong.html` 保持一致，保证存档与排序行为完全兼容。
library;

/// 宗门职务（从低到高）。
const List<String> kRoleOptions = <String>[
  '凡人',
  '外门弟子',
  '内门弟子',
  '核心弟子',
  '天骄',
  '第二天骄',
  '第一天骄',
  '执事',
  '长老',
  '峰主',
  '宗主',
  '通天塔榜首',
];

/// 职务权重，用于名单排序（越大越靠前）。
const Map<String, int> kRoleWeight = <String, int>{
  '凡人': 0,
  '外门弟子': 1,
  '内门弟子': 2,
  '核心弟子': 3,
  '天骄': 4,
  '第二天骄': 5,
  '第一天骄': 6,
  '执事': 7,
  '长老': 8,
  '峰主': 9,
  '宗主': 10,
  '通天塔榜首': 11,
};

/// 修为主阶。
const List<String> kMainRankOptions = <String>[
  '炼气',
  '筑基',
  '金丹',
  '元婴',
  '化神',
  '炼虚',
];

/// 修为小阶。
const List<String> kSubRankOptions = <String>['前期', '中期', '后期', '大圆满'];

/// 主阶分值（用于修为榜排序）。
const Map<String, int> kMainRankScore = <String, int>{
  '炼气': 1,
  '筑基': 2,
  '金丹': 3,
  '元婴': 4,
  '化神': 5,
  '炼虚': 6,
};

/// 小阶分值。
const Map<String, int> kSubRankScore = <String, int>{
  '前期': 1,
  '中期': 2,
  '后期': 3,
  '大圆满': 4,
};

/// 凡人固定境界文本。
const String kMortalRealm = '凡体';

/// 任务档次标识。
enum TaskGrade { tian, di, xuan, huang }

extension TaskGradeX on TaskGrade {
  /// 存档字段后缀：`task_tian` 等。
  String get key => switch (this) {
    TaskGrade.tian => 'tian',
    TaskGrade.di => 'di',
    TaskGrade.xuan => 'xuan',
    TaskGrade.huang => 'huang',
  };

  String get title => switch (this) {
    TaskGrade.tian => '天级任务',
    TaskGrade.di => '地级任务',
    TaskGrade.xuan => '玄级任务',
    TaskGrade.huang => '黄级任务',
  };

  String get emblem => switch (this) {
    TaskGrade.tian => '天',
    TaskGrade.di => '地',
    TaskGrade.xuan => '玄',
    TaskGrade.huang => '黄',
  };

  String get description => switch (this) {
    TaskGrade.tian => '宗门最高阶任务，凶险与机缘并存',
    TaskGrade.di => '高阶任务，核心弟子以上可接',
    TaskGrade.xuan => '中阶任务，内门弟子可接',
    TaskGrade.huang => '初阶任务，外门弟子可接',
  };
}

/// 默认可接职务。
const Map<String, List<String>> kDefaultTaskConditions = <String, List<String>>{
  'tian': <String>['天骄', '执事', '长老', '宗主'],
  'di': <String>['核心弟子', '天骄', '执事', '长老', '宗主'],
  'xuan': <String>['内门弟子', '核心弟子', '天骄', '执事', '长老', '宗主'],
  'huang': <String>['外门弟子', '内门弟子', '核心弟子', '天骄', '执事', '长老', '宗主'],
};

/// 默认管理员密码（与旧版一致）。
const String kDefaultAdminPassword = '123456';

/// 默认宗门宗旨。
const String kDefaultMotto = '落云宗：聚天地灵气，养一方道心；同门同心，其利断金。';

/// 通天塔榜首兼任职务名。
const String kChampionTitle = '通天塔榜首';

/// 每座山峰的人数上限（含峰主）。
const int kPeakCapacity = 7;

/// 立绘与头像压缩参数。
const int kAvatarMaxWidth = 256;
const int kBackgroundMaxWidth = 1920;
const int kImageQuality = 85;

/// 视频上限：20MB / 25 秒。
const int kVideoMaxBytes = 20 * 1024 * 1024;
const int kVideoMaxSeconds = 25;

/// 存档默认文件名。
const String kArchiveFileName = '落云宗存档.json';

/// 背景预设风格（与旧版 CSS 渐变一一对应）。
class BgPreset {
  const BgPreset(
    this.key,
    this.name,
    this.beginColor,
    this.endColor,
    this.glowA,
    this.glowB,
  );

  final String key;
  final String name;
  final int beginColor;
  final int endColor;
  final int glowA;
  final int glowB;
}

const List<BgPreset> kBgPresets = <BgPreset>[
  BgPreset('cloud', '青雾缭绕', 0xFF0F2036, 0xFF081022, 0x8CA9F0FF, 0x66CFE8FF),
  BgPreset('gold', '晚霞鎏金', 0xFF3A1F10, 0xFF160C06, 0x99FFB45A, 0x77C8783C),
  BgPreset('purple', '紫气东来', 0xFF2A143C, 0xFF100A1E, 0x99BE78FF, 0x55FFAADC),
  BgPreset('jade', '翠微青山', 0xFF0C2A22, 0xFF06140F, 0x88A8E6A8, 0x66805A96),
  BgPreset('night', '星辰夜幕', 0xFF0A0E1E, 0xFF04060E, 0x66A0B4FF, 0x44FFDCA0),
];

BgPreset? presetByKey(String? key) {
  for (final BgPreset p in kBgPresets) {
    if (p.key == key) return p;
  }
  return null;
}
