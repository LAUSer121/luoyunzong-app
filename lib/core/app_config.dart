/// 构建期配置：把「云端同步」直接烧进应用，界面不展示任何服务端/数据库信息。
///
/// 打包时注入（CI 里对应两个变量，本地打包同理）：
///   --dart-define=LUOYUNZONG_API_BASE=https://api.example.com
///   --dart-define=LUOYUNZONG_API_TOKEN=xxxx
///
/// 地址可以写**多个**（逗号分隔），应用启动时按顺序探测，谁通用谁：
///   --dart-define=LUOYUNZONG_API_BASE=http://127.0.0.1:8080,http://192.168.1.15:8080
/// 这样同一份安装包在「本机跑服务端」的电脑上和「家里同一个 Wi-Fi」的手机上都能连上。
///
/// 说明：数据库账号密码**只存在服务器的 .env**，应用里没有、也不会显示；
/// 界面只呈现「云端同步 / 本地存档」这类状态，不暴露地址与令牌。
/// 需要临时排查时，用 --dart-define=LUOYUNZONG_SHOW_SERVER_CONFIG=true 打包，
/// 设置页才会在解锁后出现可编辑的数据源配置。
library;

import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  /// 构建期写入的云端服务地址（空 = 未配置，走本地存档）。
  /// 支持逗号/分号/空白分隔的多个候选地址。
  static const String apiBase = String.fromEnvironment('LUOYUNZONG_API_BASE');

  /// 构建期写入的访问令牌。
  static const String apiToken = String.fromEnvironment('LUOYUNZONG_API_TOKEN');

  /// 是否允许在界面里显示/编辑服务端配置（默认关闭，避免泄露）。
  static const bool showServerConfig = bool.fromEnvironment(
    'LUOYUNZONG_SHOW_SERVER_CONFIG',
  );

  /// 是否具备云端能力。
  static bool get hasCloud => apiBase.trim().isNotEmpty;

  /// 手机端不会自己跑服务端，不必尝试回环地址。
  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 连接候选：构建期注入的地址（可多个）优先，其次本机回环（桌面/网页本地联调）。
  static List<String> get apiCandidates {
    final List<String> list = <String>[];
    void add(String raw) {
      final String value = raw.trim();
      if (value.isEmpty || list.contains(value)) return;
      list.add(value);
    }

    for (final String part in apiBase.split(RegExp(r'[,;\s]+'))) {
      add(part);
    }
    // 桌面端/网页端本地联调兜底：本机跑着 server/ 时无需额外配置。
    if (!_isMobile) {
      add('http://127.0.0.1:8080');
      add('http://localhost:8080');
    }
    return list;
  }

  /// 界面展示用的数据源名称（不含任何地址）。
  static String get dataSourceLabel => hasCloud ? '云端同步' : '本地存档';
}
