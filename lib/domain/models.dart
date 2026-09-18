/// 领域模型：与旧版存档 JSON 字段一一对应，可直接互相导入导出。
library;

import '../core/constants.dart';

int _asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double _asDouble(Object? v, [double fallback = 0]) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

String _asString(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

bool _asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

List<String> _asStringList(Object? v) {
  if (v is List) {
    return v
        .map((Object? e) => _asString(e))
        .where((String s) => s.isNotEmpty)
        .toList();
  }
  return <String>[];
}

Map<String, Object?> _asMap(Object? v) {
  if (v is Map) return v.cast<String, Object?>();
  return <String, Object?>{};
}

/// 宗门弟子。
class Member {
  Member({
    required this.name,
    required this.role,
    this.mainRank = '炼气',
    this.subRank = '前期',
    this.avatar,
    this.portrait,
    this.video,
    List<String>? subRoles,
    this.contribution = 0,
  }) : subRoles = subRoles ?? <String>[];

  factory Member.fromJson(Map<String, Object?> json) {
    return Member(
      name: _asString(json['name']),
      role: _asString(json['role'], '外门弟子'),
      mainRank: _asString(json['mainRank'], '炼气'),
      subRank: _asString(json['subRank'], '前期'),
      avatar: _nullIfEmpty(json['avatar']),
      portrait: _nullIfEmpty(json['portrait']),
      video: _nullIfEmpty(json['video']),
      subRoles: _asStringList(json['subRoles']),
      contribution: _asInt(json['contribution']),
    );
  }

  final String name;
  String role;
  String mainRank;
  String subRank;
  String? avatar;
  String? portrait;
  String? video;
  List<String> subRoles;
  int contribution;

  bool get isMortal => role == '凡人';

  /// 修为综合分：凡人 0，主阶 ×10 + 小阶。
  int get realmScore {
    if (isMortal || mainRank == kMortalRealm) return 0;
    return (kMainRankScore[mainRank] ?? 0) * 10 + (kSubRankScore[subRank] ?? 0);
  }

  /// 展示用境界文本。
  String get realmText => isMortal ? kMortalRealm : '$mainRank境$subRank';

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'role': role,
    'mainRank': mainRank,
    'subRank': subRank,
    'avatar': avatar,
    'portrait': portrait,
    'video': video,
    'subRoles': subRoles,
    'contribution': contribution,
  };

  Member copy() => Member.fromJson(toJson());
}

String? _nullIfEmpty(Object? v) {
  final String s = _asString(v);
  return s.isEmpty ? null : s;
}

/// 通天塔通关记录（保存录入时的职务/境界快照）。
class TowerRecord {
  TowerRecord({
    required this.name,
    this.role = '外门弟子',
    this.mainRank = '炼气',
    this.subRank = '前期',
    this.avatar,
    List<String>? subRoles,
    this.passCount = 0,
    this.isChampion = false,
    this.championPrevRole,
  }) : subRoles = subRoles ?? <String>[];

  factory TowerRecord.fromJson(Map<String, Object?> json) {
    return TowerRecord(
      name: _asString(json['name']),
      role: _asString(json['role'], '外门弟子'),
      mainRank: _asString(json['mainRank'], '炼气'),
      subRank: _asString(json['subRank'], '前期'),
      avatar: _nullIfEmpty(json['avatar']),
      subRoles: _asStringList(json['subRoles']),
      passCount: _asInt(json['passCount']),
      isChampion: _asBool(json['isChampion']),
      championPrevRole: _nullIfEmpty(json['championPrevRole']),
    );
  }

  final String name;
  String role;
  String mainRank;
  String subRank;
  String? avatar;
  List<String> subRoles;
  int passCount;
  bool isChampion;
  String? championPrevRole;

  int get realmScore {
    if (role == '凡人' || mainRank == kMortalRealm) return 0;
    return (kMainRankScore[mainRank] ?? 0) * 10 + (kSubRankScore[subRank] ?? 0);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'role': role,
    'mainRank': mainRank,
    'subRank': subRank,
    'avatar': avatar,
    'subRoles': subRoles,
    'passCount': passCount,
    'isChampion': isChampion,
    'championPrevRole': championPrevRole,
  };

  TowerRecord copy() => TowerRecord.fromJson(toJson());
}

/// 山峰成员：名字 + 手动维护的贡献点。
class PeakMember {
  PeakMember({required this.name, this.contribution = 0});

  factory PeakMember.fromJson(Map<String, Object?> json) => PeakMember(
    name: _asString(json['name']),
    contribution: _asInt(json['contribution']),
  );

  final String name;
  int contribution;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'contribution': contribution,
  };
}

/// 山峰。
class Peak {
  Peak({
    required this.name,
    this.avatar,
    required this.leader,
    List<PeakMember>? members,
  }) : members = members ?? <PeakMember>[];

  factory Peak.fromJson(Map<String, Object?> json) {
    final List<PeakMember> members = <PeakMember>[];
    for (final Object? e
        in (json['members'] as List<Object?>?) ?? const <Object?>[]) {
      members.add(PeakMember.fromJson(_asMap(e)));
    }
    return Peak(
      name: _asString(json['name']),
      avatar: _nullIfEmpty(json['avatar']),
      leader: _asString(json['leader']),
      members: members,
    );
  }

  final String name;
  String? avatar;
  String leader;
  List<PeakMember> members;

  int get total =>
      members.fold<int>(0, (int s, PeakMember m) => s + m.contribution);

  bool get isFull => members.length >= kPeakCapacity;

  bool has(String name) => members.any((PeakMember m) => m.name == name);

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'avatar': avatar,
    'leader': leader,
    'members': members.map((PeakMember m) => m.toJson()).toList(),
  };

  Peak copy() => Peak.fromJson(toJson());
}

/// 单场考试中的一条成绩。
class ExamRecord {
  ExamRecord({required this.name, required this.score});

  factory ExamRecord.fromJson(Map<String, Object?> json) => ExamRecord(
    name: _asString(json['name']),
    score: _asDouble(json['score']),
  );

  final String name;
  double score;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'score': score,
  };
}

/// 一场考试。
class ExamSession {
  ExamSession({
    required this.id,
    required this.name,
    this.time = '',
    List<ExamRecord>? records,
  }) : records = records ?? <ExamRecord>[];

  factory ExamSession.fromJson(Map<String, Object?> json) {
    final List<ExamRecord> records = <ExamRecord>[];
    for (final Object? e
        in (json['records'] as List<Object?>?) ?? const <Object?>[]) {
      records.add(ExamRecord.fromJson(_asMap(e)));
    }
    return ExamSession(
      id: _asString(json['id']),
      name: _asString(json['name'], '考试'),
      time: _asString(json['time']),
      records: records,
    );
  }

  final String id;
  String name;
  String time;
  List<ExamRecord> records;

  /// 按成绩降序排序后的副本。
  List<ExamRecord> get sortedRecords {
    final List<ExamRecord> copy = List<ExamRecord>.of(records);
    copy.sort((ExamRecord a, ExamRecord b) => b.score.compareTo(a.score));
    return copy;
  }

  double? scoreOf(String name) {
    for (final ExamRecord r in records) {
      if (r.name == name) return r.score;
    }
    return null;
  }

  /// 名次（1 起），未参加返回 null。
  int? rankOf(String name) {
    final List<ExamRecord> sorted = sortedRecords;
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i].name == name) return i + 1;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'time': time,
    'records': records.map((ExamRecord r) => r.toJson()).toList(),
  };

  ExamSession copy() => ExamSession.fromJson(toJson());
}

/// 成绩模块整体数据。
class ExamData {
  ExamData({
    this.threshold = 60,
    this.thresholdExcellent = 85,
    List<ExamSession>? sessions,
    this.currentSession = '',
    this.compareA = '',
    this.compareB = '',
  }) : sessions = sessions ?? <ExamSession>[];

  factory ExamData.fromJson(Map<String, Object?> json) {
    final List<ExamSession> sessions = <ExamSession>[];
    for (final Object? e
        in (json['sessions'] as List<Object?>?) ?? const <Object?>[]) {
      sessions.add(ExamSession.fromJson(_asMap(e)));
    }
    return ExamData(
      threshold: _asDouble(json['threshold'], 60),
      thresholdExcellent: _asDouble(json['thresholdExcellent'], 85),
      sessions: sessions,
      currentSession: _asString(json['currentSession']),
      compareA: _asString(json['compareA']),
      compareB: _asString(json['compareB']),
    );
  }

  double threshold;
  double thresholdExcellent;
  List<ExamSession> sessions;
  String currentSession;
  String compareA;
  String compareB;

  ExamSession? get current {
    for (final ExamSession s in sessions) {
      if (s.id == currentSession) return s;
    }
    return null;
  }

  ExamSession? sessionById(String id) {
    for (final ExamSession s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'threshold': threshold,
    'thresholdExcellent': thresholdExcellent,
    'sessions': sessions.map((ExamSession s) => s.toJson()).toList(),
    'currentSession': currentSession,
    'compareA': compareA,
    'compareB': compareB,
  };

  ExamData copy() => ExamData.fromJson(toJson());
}

/// 在线曲目（网易云）：只存元数据，播放时按 id 取流地址。
class OnlineTrack {
  OnlineTrack({
    required this.id,
    required this.name,
    this.artist = '',
    this.cover = '',
    this.durationMs = 0,
  });

  factory OnlineTrack.fromJson(Map<String, Object?> json) => OnlineTrack(
    id: _asString(json['id']),
    name: _asString(json['name']),
    artist: _asString(json['artist']),
    cover: _asString(json['cover']),
    durationMs: _asInt(json['durationMs']),
  );

  final String id;
  String name;
  String artist;
  String cover;
  int durationMs;

  String get subtitle => artist.isEmpty ? '未知歌手' : artist;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'artist': artist,
    'cover': cover,
    'durationMs': durationMs,
  };
}

/// BGM 设置。
class BgmSetting {
  BgmSetting({
    this.volume = 0.6,
    List<String>? customNames,
    List<OnlineTrack>? onlineTracks,
    this.index = 0,
    this.autoPlay = true,
  }) : customNames = customNames ?? <String>[],
       onlineTracks = onlineTracks ?? <OnlineTrack>[];

  factory BgmSetting.fromJson(Map<String, Object?> json) {
    final List<OnlineTrack> online = <OnlineTrack>[];
    for (final Object? e
        in (json['onlineTracks'] as List<Object?>?) ?? const <Object?>[]) {
      final OnlineTrack track = OnlineTrack.fromJson(_asMap(e));
      if (track.id.isNotEmpty) online.add(track);
    }
    return BgmSetting(
      volume: _asDouble(json['volume'], 0.6).clamp(0, 1).toDouble(),
      customNames: _asStringList(json['customNames']),
      onlineTracks: online,
      index: _asInt(json['index']),
      autoPlay: _asBool(json['autoPlay'], true),
    );
  }

  double volume;
  List<String> customNames;

  /// 在线修仙电台曲目（网易云）。
  List<OnlineTrack> onlineTracks;
  int index;

  /// 启动后是否自动播放 BGM。
  bool autoPlay;

  Map<String, Object?> toJson() => <String, Object?>{
    'volume': volume,
    'customNames': customNames,
    'onlineTracks': onlineTracks.map((OnlineTrack t) => t.toJson()).toList(),
    'index': index,
    'autoPlay': autoPlay,
  };
}

/// 背景设置：默认 / 预设风格 / 自定义图片。
enum BgType { preset, image }

class BackgroundSetting {
  BackgroundSetting({this.type, this.key, this.data})
    : assert(type != BgType.preset || key != null, '预设背景必须带 key');

  factory BackgroundSetting.fromJson(Map<String, Object?> json) {
    final String t = _asString(json['type'], 'default');
    if (t == 'preset') {
      return BackgroundSetting(
        type: BgType.preset,
        key: _asString(json['key']),
      );
    }
    if (t == 'image') {
      return BackgroundSetting(
        type: BgType.image,
        data: _nullIfEmpty(json['data']),
      );
    }
    return BackgroundSetting.defaults();
  }

  factory BackgroundSetting.defaults() => BackgroundSetting();

  final BgType? type;
  final String? key;
  final String? data;

  bool get isDefault => type == null;

  String get label {
    if (type == BgType.preset) return presetByKey(key)?.name ?? '预设风格';
    if (type == BgType.image) return '自定义图片';
    return '默认背景';
  }

  Map<String, Object?> toJson() {
    if (type == BgType.preset) {
      return <String, Object?>{'type': 'preset', 'key': key};
    }
    if (type == BgType.image) {
      return <String, Object?>{'type': 'image', 'data': data};
    }
    return <String, Object?>{'type': 'default'};
  }
}

/// 完整存档，字段名与旧版 `buildArchive()` 一致。
class Archive {
  Archive({
    this.archiveVersion = 4,
    this.adminPassword = kDefaultAdminPassword,
    List<Member>? memberList,
    List<TowerRecord>? towerList,
    Map<String, List<String>>? taskConditions,
    Map<String, String>? tasks,
    this.notice = '',
    this.updateText = '',
    BgmSetting? bgm,
    BackgroundSetting? background,
    List<Peak>? peakList,
    this.motto = kDefaultMotto,
    ExamData? examData,
  }) : memberList = memberList ?? <Member>[],
       towerList = towerList ?? <TowerRecord>[],
       taskConditions = taskConditions ?? _defaultConditions(),
       tasks = tasks ?? _defaultTasks(),
       bgm = bgm ?? BgmSetting(),
       background = background ?? BackgroundSetting.defaults(),
       peakList = peakList ?? <Peak>[],
       examData = examData ?? ExamData();

  factory Archive.fromJson(Map<String, Object?> json) {
    final List<Member> members = <Member>[];
    for (final Object? e
        in (json['memberList'] as List<Object?>?) ?? const <Object?>[]) {
      members.add(Member.fromJson(_asMap(e)));
    }
    final List<TowerRecord> towers = <TowerRecord>[];
    for (final Object? e
        in (json['towerList'] as List<Object?>?) ?? const <Object?>[]) {
      towers.add(TowerRecord.fromJson(_asMap(e)));
    }
    final List<Peak> peaks = <Peak>[];
    for (final Object? e
        in (json['peakList'] as List<Object?>?) ?? const <Object?>[]) {
      peaks.add(Peak.fromJson(_asMap(e)));
    }

    final Map<String, List<String>> conditions = _defaultConditions();
    final Map<String, Object?> rawConds = _asMap(json['taskConditions']);
    for (final String key in conditions.keys.toList()) {
      if (rawConds.containsKey(key)) {
        conditions[key] = _asStringList(rawConds[key]);
      }
    }

    final Map<String, String> tasks = <String, String>{
      'tian': _asString(json['task_tian']),
      'di': _asString(json['task_di']),
      'xuan': _asString(json['task_xuan']),
      'huang': _asString(json['task_huang']),
    };

    final Archive archive = Archive(
      archiveVersion: _asInt(json['archiveVersion'], 4),
      adminPassword: _asString(json['adminPassword'], kDefaultAdminPassword),
      memberList: members,
      towerList: towers,
      taskConditions: conditions,
      tasks: tasks,
      notice: _asString(json['notice']),
      updateText: _asString(json['update']),
      bgm: BgmSetting.fromJson(_asMap(json['bgm'])),
      background: BackgroundSetting.fromJson(_asMap(json['bg'])),
      peakList: peaks,
      motto: _asString(json['motto'], kDefaultMotto),
      examData: migrateExamData(_asMap(json['examData'])),
    );
    archive.sortMembers();
    return archive;
  }

  int archiveVersion;
  String adminPassword;
  List<Member> memberList;
  List<TowerRecord> towerList;
  Map<String, List<String>> taskConditions;
  Map<String, String> tasks;
  String notice;
  String updateText;
  BgmSetting bgm;
  BackgroundSetting background;
  List<Peak> peakList;
  String motto;
  ExamData examData;

  Map<String, Object?> toJson() => <String, Object?>{
    'archiveVersion': archiveVersion,
    'adminPassword': adminPassword,
    'memberList': memberList.map((Member m) => m.toJson()).toList(),
    'towerList': towerList.map((TowerRecord t) => t.toJson()).toList(),
    'taskConditions': taskConditions,
    'task_tian': tasks['tian'] ?? '',
    'task_di': tasks['di'] ?? '',
    'task_xuan': tasks['xuan'] ?? '',
    'task_huang': tasks['huang'] ?? '',
    'notice': notice,
    'update': updateText,
    'bgm': bgm.toJson(),
    'bg': background.toJson(),
    'peakList': peakList.map((Peak p) => p.toJson()).toList(),
    'motto': motto,
    'examData': examData.toJson(),
  };

  Archive copy() => Archive.fromJson(toJson());

  Member? memberByName(String name) {
    for (final Member m in memberList) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// 按职务权重重排名单（通天塔榜首 > 宗主 > 峰主 > 长老 > … > 凡人）。
  void sortMembers() {
    memberList.sort(
      (Member a, Member b) =>
          (kRoleWeight[b.role] ?? 0).compareTo(kRoleWeight[a.role] ?? 0),
    );
  }
}

Map<String, List<String>> _defaultConditions() {
  return <String, List<String>>{
    for (final MapEntry<String, List<String>> e
        in kDefaultTaskConditions.entries)
      e.key: List<String>.of(e.value),
  };
}

Map<String, String> _defaultTasks() => <String, String>{
  'tian': '',
  'di': '',
  'xuan': '',
  'huang': '',
};

/// 旧档迁移：把 `categories[].sessions[]` / `categories[].records[]` 扁平化。
ExamData migrateExamData(Map<String, Object?> raw) {
  final List<ExamSession> sessions = <ExamSession>[];
  double threshold = 60;
  double excellent = 85;

  final List<Object?> cats =
      (raw['categories'] as List<Object?>?) ?? const <Object?>[];
  if (cats.isNotEmpty) {
    final Map<String, Object?> first = _asMap(cats.first);
    // 旧版把分数线放在 categories[0]；同时兼容放在根节点的新格式。
    threshold = _asDouble(raw['threshold'], _asDouble(first['threshold'], 60));
    excellent = _asDouble(
      raw['thresholdExcellent'],
      _asDouble(first['thresholdExcellent'], 85),
    );
  }
  for (final Object? c in cats) {
    final Map<String, Object?> cat = _asMap(c);
    final List<Object?> catSessions =
        (cat['sessions'] as List<Object?>?) ?? const <Object?>[];
    for (final Object? s in catSessions) {
      sessions.add(ExamSession.fromJson(_asMap(s)));
    }
    if (catSessions.isEmpty) {
      final List<Object?> recs =
          (cat['records'] as List<Object?>?) ?? const <Object?>[];
      if (recs.isNotEmpty) {
        sessions.add(
          ExamSession(
            id: newSessionId(),
            name: _asString(cat['name'], '历史记录'),
            records: recs
                .map((Object? e) => ExamRecord.fromJson(_asMap(e)))
                .toList(),
          ),
        );
      }
    }
  }

  if (raw['sessions'] is List) {
    sessions
      ..clear()
      ..addAll(
        (raw['sessions'] as List<Object?>)
            .map((Object? e) => ExamSession.fromJson(_asMap(e)))
            .map(
              (ExamSession s) => s.id.isEmpty
                  ? ExamSession(
                      id: newSessionId(),
                      name: s.name,
                      time: s.time,
                      records: s.records,
                    )
                  : s,
            ),
      );
    threshold = _asDouble(raw['threshold'], threshold);
    excellent = _asDouble(raw['thresholdExcellent'], excellent);
  }

  final ExamData data = ExamData(
    threshold: threshold,
    thresholdExcellent: excellent,
    sessions: sessions,
  );
  final String current = _asString(raw['currentSession']);
  data.currentSession = sessions.any((ExamSession s) => s.id == current)
      ? current
      : (sessions.isEmpty ? '' : sessions.last.id);
  final String a = _asString(raw['compareA']);
  final String b = _asString(raw['compareB']);
  data.compareA = sessions.any((ExamSession s) => s.id == a) ? a : '';
  data.compareB = sessions.any((ExamSession s) => s.id == b) ? b : '';
  return data;
}

int _sessionSeq = 0;

/// 场次 id，格式与旧版 `genSessionId()` 类似：`s` + 时间戳 36 进制 + 序号。
String newSessionId() {
  _sessionSeq = (_sessionSeq + 1) % 1000;
  return 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_sessionSeq.toRadixString(36)}';
}
