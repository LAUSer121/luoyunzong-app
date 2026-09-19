/// 全局状态：唯一可变数据源 + 自动保存 + 全部业务动作。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/image_utils.dart';
import '../core/parsers.dart';
import '../data/archive_codec.dart';
import '../data/local_repository.dart';
import '../data/netease_client.dart';
import '../data/settings_store.dart';
import '../data/wallpaper_client.dart';
import '../domain/models.dart';
import '../domain/repository.dart';
import 'bgm_controller.dart';
import 'sync_manager.dart';

class AppState extends ChangeNotifier {
  AppState({LuoyunRepository? repository, this.localStore, this.settings})
    : repository = repository ?? LocalRepository(),
      archive = Archive();

  final LuoyunRepository repository;

  /// 本地存档仓储：云同步的快照（冲突备份）固定写在本机，不随云端走。
  final LocalRepository? localStore;

  /// 设备本地设置（自动同步开关、上次同步时间等只存本机）。
  final SettingsStore? settings;

  /// 云同步引擎（由 main 装配；未配置云端时为 null）。
  SyncManager? sync;

  /// 本机最后一次「真正改动内容」的时间，用于判断云端与我这边谁更新。
  DateTime? _lastLocalChangeAt;

  DateTime? get lastLocalChangeAt => _lastLocalChangeAt;

  /// 载入设备本地保存的最后改动时间（启动时从 SharedPreferences 恢复）。
  void restoreLocalChangeAt(DateTime? at) {
    _lastLocalChangeAt = at;
  }

  /// 标记「本地刚改过」：既用于云同步判断，也触发自动同步的延迟推送。
  void markLocalChanged() {
    final DateTime now = DateTime.now();
    _lastLocalChangeAt = now;
    final SettingsStore? store = settings;
    if (store != null) unawaited(store.setLastLocalChangeAt(now));
    sync?.onLocalChange();
  }

  /// 同步完成后对齐时间戳（避免把同一份数据反复推拉）。
  Future<void> markSyncedAt(DateTime at) async {
    _lastLocalChangeAt = at;
    await settings?.setLastLocalChangeAt(at);
  }

  /// 把云端存档写入本地（不视为本地新改动），并刷新曲单等派生数据。
  Future<void> applyRemoteArchive(Archive remote) async {
    archive = remote;
    _dirty = true;
    notifyListeners();
    await _persist();
    unawaited(
      bgm
          .syncFromArchive(archive)
          .catchError((Object _) => bgm.markUnavailable()),
    );
  }

  /// 同步时留一份本机快照（冲突时保留落败的一份，可手动恢复）。
  Future<void> writeSyncSnapshot(String json) async {
    await localStore?.writeSnapshot(json);
  }

  Future<String?> readSyncSnapshot() async => localStore?.readSnapshot();

  /// BGM 播放控制器（曲单与存档同步）。
  final BgmController bgm = BgmController();

  /// 网易云在线搜索客户端（可在设置里配置代理地址，解决 Web 端跨域）。
  NeteaseClient netease = NeteaseClient();

  /// 在线仙侠背景客户端（Wallhaven / Picsum）。
  final WallpaperClient wallpapers = WallpaperClient();

  Archive archive;

  bool _ready = false;
  bool _unlocked = false;
  bool _dirty = false;
  String? _lastError;
  Timer? _saveTimer;

  /// 初始化是否完成（用于首屏 loading）。
  bool get ready => _ready;

  /// 是否已解锁编辑权限。
  bool get unlocked => _unlocked;

  /// 是否有未落盘的改动。
  bool get dirty => _dirty;

  /// 最近一次错误提示（保存失败等）。
  String? get lastError => _lastError;

  /// 存档位置描述。
  String get storageLabel => repository.label;

  Future<String?> storageLocation() async {
    final LuoyunRepository r = repository;
    if (r is LocalRepository) return r.location();
    return null;
  }

  // ------------------------------------------------------------------
  // 生命周期
  // ------------------------------------------------------------------

  /// 读取本地/远端存档；无存档时使用空存档。
  Future<void> init() async {
    try {
      final Archive? loaded = await repository.load();
      if (loaded != null) archive = loaded;
      _lastError = null;
    } catch (e) {
      _lastError = '读取存档失败：$e';
    } finally {
      _ready = true;
      notifyListeners();
    }
    bgm.netease = netease;
    bgm.bindPlayerEvents();
    // BGM 是附带能力：不阻塞启动，出错也不影响数据加载（各平台行为一致）。
    unawaited(
      bgm
          .syncFromArchive(archive)
          .catchError((Object _) => bgm.markUnavailable()),
    );
  }

  /// 立即保存（忽略防抖）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return;
    await _persist();
  }

  /// 变更存档并触发防抖自动保存。
  void mutate(void Function(Archive a) body, {bool persist = true}) {
    body(archive);
    _dirty = true;
    // 内容改动即记时间戳：云同步据此判断「本地比云端新」。
    markLocalChanged();
    notifyListeners();
    if (!persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    try {
      await repository.save(archive);
      _dirty = false;
      _lastError = null;
    } catch (e) {
      _lastError = '保存失败：$e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    bgm.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 权限
  // ------------------------------------------------------------------

  bool unlock(String password) {
    final bool ok = password == archive.adminPassword;
    if (ok) {
      _unlocked = true;
      notifyListeners();
    }
    return ok;
  }

  void lock() {
    _unlocked = false;
    notifyListeners();
  }

  /// 修改管理员密码；长度不足或旧密码错误返回错误文案。
  String? changePassword(String oldPwd, String newPwd, String confirmPwd) {
    if (oldPwd != archive.adminPassword) return '旧密码不正确';
    if (newPwd.length < 4) return '新密码至少 4 位';
    if (newPwd != confirmPwd) return '两次输入的新密码不一致';
    mutate((Archive a) => a.adminPassword = newPwd);
    return null;
  }

  // ------------------------------------------------------------------
  // 存档导入导出
  // ------------------------------------------------------------------

  /// 用文本内容替换当前存档，返回 null 表示成功，否则为错误文案。
  String? importArchiveText(String text, {bool keepUnlocked = true}) {
    final Archive? parsed = ArchiveCodec.decode(text);
    if (parsed == null) return '存档文件格式错误，未导入任何数据';
    archive = parsed;
    _unlocked = keepUnlocked ? _unlocked : false;
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
    return null;
  }

  /// 导出为旧版可读的 JS 存档文本。
  String exportJs() => ArchiveCodec.encodeJs(archive);

  /// 导出为 JSON 文本。
  String exportJson() => ArchiveCodec.encodeJson(archive);

  /// 清空全部数据（保留密码）。
  void clearAll() {
    final String pwd = archive.adminPassword;
    archive = Archive(adminPassword: pwd);
    _dirty = true;
    notifyListeners();
    unawaited(_persist());
  }

  // ------------------------------------------------------------------
  // 宗门名单
  // ------------------------------------------------------------------

  void addMember({
    required String name,
    required String role,
    required String mainRank,
    required String subRank,
    String? avatar,
  }) {
    mutate((Archive a) {
      final String main = role == '凡人' ? kMortalRealm : mainRank;
      final String sub = role == '凡人' ? '' : subRank;
      a.memberList.add(
        Member(
          name: name,
          role: role,
          mainRank: main,
          subRank: sub,
          avatar: avatar,
          subRoles: <String>[],
        ),
      );
      a.sortMembers();
    });
  }

  /// 批量导入名单，返回统计结果。
  MemberParseResult importMembers(String text) {
    final Set<String> existing = archive.memberList
        .map((Member m) => m.name)
        .toSet();
    final MemberParseResult result = parseMemberLines(text, existing);
    if (result.added.isNotEmpty) {
      mutate((Archive a) {
        a.memberList.addAll(result.added);
        a.sortMembers();
      });
    }
    return result;
  }

  void updateMember(
    String name, {
    String? role,
    String? mainRank,
    String? subRank,
    int? contribution,
    List<String>? subRoles,
  }) {
    mutate((Archive a) {
      final Member? m = a.memberByName(name);
      if (m == null) return;
      if (role != null && role != m.role) {
        m.role = role;
        m.subRoles.remove(role);
        if (role == '凡人') {
          m.mainRank = kMortalRealm;
          m.subRank = '';
        } else if (m.mainRank == kMortalRealm) {
          m.mainRank = '炼气';
          m.subRank = '前期';
        }
      }
      if (role == null || role != '凡人') {
        if (mainRank != null) m.mainRank = mainRank;
        if (subRank != null) m.subRank = subRank;
      }
      if (contribution != null) {
        m.contribution = contribution < 0 ? 0 : contribution;
      }
      if (subRoles != null) m.subRoles = List<String>.of(subRoles);
      a.sortMembers();
    });
  }

  void deleteMember(String name) {
    mutate((Archive a) {
      a.memberList.removeWhere((Member m) => m.name == name);
      // 通天塔记录与山峰成员随之清理，避免出现「已离宗」悬空数据
      a.towerList.removeWhere((TowerRecord t) => t.name == name);
      for (final Peak p in a.peakList) {
        p.members.removeWhere((PeakMember m) => m.name == name);
      }
      a.peakList.removeWhere((Peak p) => p.members.isEmpty);
    });
  }

  void setPortrait(String name, String? dataUrl) {
    mutate(
      (Archive a) => a.memberByName(name)?.portrait = dataUrl,
      persist: false,
    );
    unawaited(_persist());
  }

  void setVideo(String name, String? dataUrl) {
    mutate(
      (Archive a) => a.memberByName(name)?.video = dataUrl,
      persist: false,
    );
    unawaited(_persist());
  }

  void setAvatar(String name, String? dataUrl) {
    mutate(
      (Archive a) => a.memberByName(name)?.avatar = dataUrl,
      persist: false,
    );
    unawaited(_persist());
  }

  // ------------------------------------------------------------------
  // 宗门任务 / 公告 / 更新内容 / 宗旨
  // ------------------------------------------------------------------

  void setTaskText(TaskGrade grade, String text) =>
      mutate((Archive a) => a.tasks[grade.key] = text);

  void setTaskConditions(TaskGrade grade, List<String> roles) => mutate(
    (Archive a) => a.taskConditions[grade.key] = List<String>.of(roles),
  );

  void setNotice(String text) => mutate((Archive a) => a.notice = text);

  void setUpdateText(String text) => mutate((Archive a) => a.updateText = text);

  void setMotto(String text) => mutate(
    (Archive a) => a.motto = text.trim().isEmpty ? kDefaultMotto : text.trim(),
  );

  // ------------------------------------------------------------------
  // 通天塔
  // ------------------------------------------------------------------

  /// 添加通关记录；成员不存在返回错误文案。
  String? addTowerRecord(String name, int passCount) {
    final Member? m = archive.memberByName(name);
    if (m == null) return '未找到该弟子：$name（请先录入宗门名单）';
    mutate((Archive a) {
      a.towerList.add(
        TowerRecord(
          name: m.name,
          role: m.role,
          mainRank: m.mainRank,
          subRank: m.subRank,
          avatar: m.avatar,
          subRoles: List<String>.of(m.subRoles),
          passCount: passCount,
        ),
      );
      _sortTower(a);
    });
    return null;
  }

  void updateTowerRecord(String name, int passCount) {
    mutate((Archive a) {
      for (final TowerRecord t in a.towerList) {
        if (t.name == name) t.passCount = passCount < 0 ? 0 : passCount;
      }
      _sortTower(a);
    });
  }

  void deleteTowerRecord(String name) => mutate(
    (Archive a) => a.towerList.removeWhere((TowerRecord t) => t.name == name),
  );

  void setTowerChampion(String name) {
    mutate((Archive a) {
      // 换榜首时先摘掉原榜首的荣誉职衔，保证同一时间只有一位
      final List<String> previous = <String>[
        for (final TowerRecord t in a.towerList)
          if (t.isChampion && t.name != name) t.name,
      ];
      for (final String prev in previous) {
        a.memberByName(prev)?.subRoles.remove(kChampionTitle);
      }
      for (final TowerRecord t in a.towerList) {
        t.isChampion = t.name == name;
      }
      _sortTower(a);
      final Member? m = a.memberByName(name);
      if (m != null && !m.subRoles.contains(kChampionTitle)) {
        m.subRoles.add(kChampionTitle);
      }
    });
  }

  void unsetTowerChampion(String name) {
    mutate((Archive a) {
      for (final TowerRecord t in a.towerList) {
        if (t.name == name) t.isChampion = false;
      }
      _sortTower(a);
      a.memberByName(name)?.subRoles.remove(kChampionTitle);
    });
  }

  // ------------------------------------------------------------------
  // 山峰
  // ------------------------------------------------------------------

  String? createPeak({
    required String name,
    required String leader,
    String? avatar,
  }) {
    if (name.trim().isEmpty) return '请输入山峰名称';
    if (archive.peakList.any((Peak p) => p.name == name)) return '山峰名称已存在';
    if (archive.memberByName(leader) == null) return '峰主必须是宗门名单中的成员';
    mutate((Archive a) {
      a.peakList.add(
        Peak(
          name: name,
          avatar: avatar,
          leader: leader,
          members: <PeakMember>[PeakMember(name: leader)],
        ),
      );
    });
    return null;
  }

  /// 可入峰成员：未在任意山峰、且非凡人。
  List<Member> freeForPeak() {
    final Set<String> taken = <String>{
      for (final Peak p in archive.peakList)
        for (final PeakMember m in p.members) m.name,
    };
    return archive.memberList
        .where((Member m) => !taken.contains(m.name) && m.role != '凡人')
        .toList();
  }

  String? addPeakMember(String peakName, String memberName) {
    final Peak? p = _peakByName(peakName);
    if (p == null) return '山峰不存在';
    if (p.isFull) return '该峰已达 $kPeakCapacity 人上限';
    if (p.has(memberName)) return '该弟子已在此峰';
    Peak? other;
    for (final Peak p in archive.peakList) {
      if (p.has(memberName)) {
        other = p;
        break;
      }
    }
    if (other != null) return '该弟子已归属山峰「${other.name}」，每人只能归属一座山峰';
    mutate(
      (Archive a) =>
          _peakByName(peakName, a)?.members.add(PeakMember(name: memberName)),
    );
    return null;
  }

  String? removePeakMember(String peakName, String memberName) {
    final Peak? p = _peakByName(peakName);
    if (p == null) return '山峰不存在';
    if (p.leader == memberName) return '峰主不可移除，请先改任峰主';
    mutate(
      (Archive a) => _peakByName(
        peakName,
        a,
      )?.members.removeWhere((PeakMember m) => m.name == memberName),
    );
    return null;
  }

  void setPeakLeader(String peakName, String memberName) => mutate((Archive a) {
    final Peak? p = _peakByName(peakName, a);
    if (p == null) return;
    p.leader = memberName;
  });

  void updatePeakContribution(String peakName, String memberName, int value) =>
      mutate((Archive a) {
        final Peak? p = _peakByName(peakName, a);
        if (p == null) return;
        for (final PeakMember m in p.members) {
          if (m.name == memberName) m.contribution = value < 0 ? 0 : value;
        }
      });

  void deletePeak(String peakName) => mutate(
    (Archive a) => a.peakList.removeWhere((Peak p) => p.name == peakName),
  );

  void setPeakAvatar(String peakName, String? dataUrl) {
    mutate(
      (Archive a) => _peakByName(peakName, a)?.avatar = dataUrl,
      persist: false,
    );
    unawaited(_persist());
  }

  Peak? _peakByName(String name, [Archive? a]) {
    final Archive target = a ?? archive;
    for (final Peak p in target.peakList) {
      if (p.name == name) return p;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // 成绩
  // ------------------------------------------------------------------

  String? newExamSession({required String name, String time = ''}) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '请输入考试名称';
    if (archive.examData.sessions.any((ExamSession s) => s.name == trimmed)) {
      return '已存在同名考试，请换一个名称';
    }
    mutate((Archive a) {
      final ExamSession s = ExamSession(
        id: newSessionId(),
        name: trimmed,
        time: time.trim().isEmpty ? nowTimeStr() : time.trim(),
      );
      a.examData.sessions.add(s);
      a.examData.currentSession = s.id;
    });
    return null;
  }

  void deleteExamSession(String id) => mutate((Archive a) {
    a.examData.sessions.removeWhere((ExamSession s) => s.id == id);
    if (a.examData.currentSession == id) {
      a.examData.currentSession = a.examData.sessions.isEmpty
          ? ''
          : a.examData.sessions.last.id;
    }
    if (a.examData.compareA == id) a.examData.compareA = '';
    if (a.examData.compareB == id) a.examData.compareB = '';
  });

  void switchExamSession(String id) =>
      mutate((Archive a) => a.examData.currentSession = id);

  void setCompare(String a, [String? b]) => mutate((Archive ar) {
    ar.examData.compareA = a;
    if (b != null) ar.examData.compareB = b;
  });

  void saveThreshold(double threshold, double excellent) => mutate((Archive a) {
    a.examData.threshold = threshold;
    a.examData.thresholdExcellent = excellent;
  });

  /// 从文本导入成绩：生成新场次，并返回提示文案。
  String importScoresFromText({
    required String name,
    required String text,
    String time = '',
  }) {
    final ScoreParseResult parsed = parseScoreLines(text);
    if (parsed.valid.isEmpty) return '未解析到有效成绩行，请检查格式（每行：姓名 成绩）';
    return createSessionFromRecords(
      name: name,
      records: parsed.valid,
      time: time,
      badLines: parsed.invalid,
    );
  }

  /// 由解析结果创建场次；返回提示文案（失败时以「失败：」开头）。
  String createSessionFromRecords({
    required String name,
    required List<ExamRecord> records,
    String time = '',
    List<String> badLines = const <String>[],
    bool reportUnmatched = true,
  }) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '失败：请先填写考试名称';
    if (archive.examData.sessions.any((ExamSession s) => s.name == trimmed)) {
      return '失败：已存在同名考试「$trimmed」，请换一个名称';
    }
    final List<ExamRecord> valid = <ExamRecord>[];
    final List<String> unmatched = <String>[];
    for (final ExamRecord r in records) {
      if (archive.memberByName(r.name) == null) {
        unmatched.add('${r.name}(${formatNumber(r.score)})');
        continue;
      }
      valid.add(ExamRecord(name: r.name, score: r.score));
    }
    if (valid.isEmpty) return '失败：没有匹配到宗门名单中的成员，请先录入名单';
    mutate((Archive a) {
      final ExamSession s = ExamSession(
        id: newSessionId(),
        name: trimmed,
        time: time.trim().isEmpty ? nowTimeStr() : time.trim(),
        records: valid,
      );
      a.examData.sessions.add(s);
      a.examData.currentSession = s.id;
    });
    final StringBuffer msg = StringBuffer(
      '已导入为新场次「$trimmed」：成功 ${valid.length} 条',
    );
    if (reportUnmatched && unmatched.isNotEmpty) {
      msg.write('\n未匹配到宗门名单（已跳过）：${unmatched.take(12).join('、')}');
      if (unmatched.length > 12) msg.write('…');
    }
    if (badLines.isNotEmpty) {
      msg.write('\n无法识别的行（已跳过）：${badLines.take(8).join('、')}');
      if (badLines.length > 8) msg.write('…');
    }
    return msg.toString();
  }

  /// 追加/更新当前场次的一条成绩。
  void addExamRecord(String name, double score) {
    mutate((Archive a) {
      final ExamSession? s = a.examData.current;
      if (s == null) return;
      for (final ExamRecord r in s.records) {
        if (r.name == name) {
          r.score = score;
          return;
        }
      }
      s.records.add(ExamRecord(name: name, score: score));
    });
  }

  void updateExamScore(String sessionId, String name, double score) {
    mutate((Archive a) {
      final ExamSession? s = a.examData.sessionById(sessionId);
      if (s == null) return;
      for (final ExamRecord r in s.records) {
        if (r.name == name) r.score = score;
      }
    });
  }

  void deleteExamRecord(String sessionId, String name) {
    mutate((Archive a) {
      final ExamSession? s = a.examData.sessionById(sessionId);
      s?.records.removeWhere((ExamRecord r) => r.name == name);
    });
  }

  // ------------------------------------------------------------------
  // 背景 / BGM 设置（BGM 播放由 BgmController 负责）
  // ------------------------------------------------------------------

  void setBackgroundPreset(String key) => mutate(
    (Archive a) => a.background = BackgroundSetting(
      type: BgType.preset,
      key: key,
      autoOnline: a.background.autoOnline,
    ),
  );

  void setBackgroundImage(String dataUrl) => mutate(
    (Archive a) => a.background = BackgroundSetting(
      type: BgType.image,
      data: dataUrl,
      autoOnline: a.background.autoOnline,
    ),
  );

  void resetBackground() => mutate(
    (Archive a) =>
        a.background = BackgroundSetting(autoOnline: a.background.autoOnline),
  );

  /// 启动时自动获取在线背景的开关。
  void setAutoOnlineBackground(bool value) => mutate(
    (Archive a) => a.background = a.background.copyWith(autoOnline: value),
  );

  /// 从网上随机拉一张仙侠背景并应用；成功返回 `null`，失败返回错误文案。
  ///
  /// 图源顺序：Wallhaven → 必应图片搜索 → 必应每日壁纸 → Picsum（见 WallpaperClient）。
  Future<String?> fetchOnlineBackground({String? query}) async {
    final WallpaperPick? pick = await wallpapers.pick(query: query);
    if (pick == null) return '没有获取到在线背景（网络或图源限制）';
    final String? dataUrl = compressImageToDataUrl(
      pick.bytes,
      maxWidth: kBackgroundMaxWidth,
      quality: kImageQuality,
    );
    if (dataUrl == null) return '背景图片解析失败';
    mutate(
      (Archive a) => a.background = BackgroundSetting(
        type: BgType.image,
        data: dataUrl,
        credit: pick.wallpaper.credit,
        autoOnline: a.background.autoOnline,
      ),
    );
    return null;
  }

  /// 启动时按开关自动换一张在线背景（失败静默，不打扰启动流程）。
  Future<void> maybeAutoFetchBackground() async {
    if (!archive.background.autoOnline) return;
    await fetchOnlineBackground();
  }

  void setBgmVolume(double volume) =>
      mutate((Archive a) => a.bgm.volume = volume.clamp(0, 1).toDouble());

  /// 启动自动播放开关。
  void setBgmAutoPlay(bool value) =>
      mutate((Archive a) => a.bgm.autoPlay = value);

  /// 是否允许启动后自动播放。
  bool get bgmAutoPlay => archive.bgm.autoPlay;

  /// 启动时自动播放：曲单为空则自动挑选仙侠电台，否则播放已有曲目。
  Future<void> autoStartBgm() async {
    if (!bgmAutoPlay) return;
    if (bgm.tracks.isNotEmpty) {
      await bgm.autoStart();
      return;
    }
    await bgm.autoFillXianxia(playNow: true);
  }

  /// 在线搜索客户端使用的代理地址（空表示直连官方接口）。
  void setNeteaseBase(String apiBase) {
    netease.close();
    netease = NeteaseClient(apiBase: apiBase);
    bgm.netease = netease;
    notifyListeners();
  }

  /// 把在线曲目加入永久曲单。
  void addOnlineTrack(OnlineTrack track) {
    mutate((Archive a) {
      if (a.bgm.onlineTracks.any((OnlineTrack t) => t.id == track.id)) return;
      a.bgm.onlineTracks.add(track);
    });
    bgm.addOnlineTrack(track);
  }

  /// 从永久曲单移除在线曲目。
  void removeOnlineTrack(String id) {
    mutate(
      (Archive a) =>
          a.bgm.onlineTracks.removeWhere((OnlineTrack t) => t.id == id),
    );
    unawaited(bgm.syncFromArchive(archive));
  }

  void setBgmIndex(int index) => mutate((Archive a) => a.bgm.index = index);

  /// 添加同目录文件名到曲单（随存档保存）。
  bool addBgmName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (archive.bgm.customNames.contains(trimmed)) return false;
    mutate((Archive a) {
      a.bgm.customNames.add(trimmed);
      a.bgm.index = a.bgm.customNames.length - 1;
    });
    unawaited(bgm.syncFromArchive(archive));
    return true;
  }

  void removeBgmName(String name) {
    mutate((Archive a) {
      a.bgm.customNames.remove(name);
      if (a.bgm.index >= a.bgm.customNames.length) {
        a.bgm.index = a.bgm.customNames.isEmpty
            ? 0
            : a.bgm.customNames.length - 1;
      }
    });
    unawaited(bgm.syncFromArchive(archive));
  }

  /// 曲单新增本地音乐（落盘到应用数据目录，随存档长期保留）。
  Future<String?> addBgmFiles(
    List<({String name, Uint8List bytes})> files,
  ) async {
    final String? msg = await bgm.addFiles(files);
    for (final ({String name, Uint8List bytes}) f in files) {
      if (!archive.bgm.customNames.contains(f.name) && await _stored(f.name)) {
        mutate((Archive a) {
          a.bgm.customNames.add(f.name);
          a.bgm.index = a.bgm.customNames.length - 1;
        });
      }
    }
    return msg;
  }

  Future<bool> _stored(String name) async {
    // 会话曲目（无法落盘）不写入存档，避免下次启动找不到文件
    return bgm.tracks.any((BgmTrack t) => t.name == name && !t.sessionOnly);
  }

  /// 从曲单移除（同时删除应用数据目录中的文件）。
  Future<void> removeBgmTrack(int index) async {
    final BgmTrack? t = (index >= 0 && index < bgm.tracks.length)
        ? bgm.tracks[index]
        : null;
    await bgm.removeTrack(index);
    if (t != null && !t.sessionOnly) {
      mutate((Archive a) => a.bgm.customNames.remove(t.name));
    }
    notifyListeners();
  }
}

void _sortTower(Archive a) {
  a.towerList.sort((TowerRecord x, TowerRecord y) {
    if (x.isChampion != y.isChampion) return x.isChampion ? -1 : 1;
    return y.passCount.compareTo(x.passCount);
  });
}
