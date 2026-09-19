/// 构建期配置：把「云端同步」直接烧进应用，界面不展示任何服务端/数据库信息。
///
/// 打包时注入（CI 里对应两个变量，本地打包同理）：
///   --dart-define=LUOYUNZONG_API_BASE=https://api.example.com
///   --dart-define=LUOYUNZONG_API_TOKEN=xxxx
///
/// 说明：数据库账号密码**只存在服务器的 .env**，应用里没有、也不会显示；
/// 界面只呈现「云端同步 / 本地存档」这类状态，不暴露地址与令牌。
/// 需要临时排查时，用 --dart-define=LUOYUNZONG_SHOW_SERVER_CONFIG=true 打包，
/// 设置页才会在解锁后出现可编辑的数据源配置。
library;

class AppConfig {
  const AppConfig._();

  /// 构建期写入的云端服务地址（空 = 未配置，走本地存档）。
  static const String apiBase = String.fromEnvironment('LUOYUNZONG_API_BASE');

  /// 构建期写入的访问令牌。
  static const String apiToken = String.fromEnvironment('LUOYUNZONG_API_TOKEN');

  /// 是否允许在界面里显示/编辑服务端配置（默认关闭，避免泄露）。
  static const bool showServerConfig = bool.fromEnvironment(
    'LUOYUNZONG_SHOW_SERVER_CONFIG',
  );

  /// 是否具备云端能力。
  static bool get hasCloud => apiBase.trim().isNotEmpty;

  /// 连接候选：构建期地址优先，其次本机（方便开发时本机跑服务端联调）。
  static List<String> get apiCandidates {
    final List<String> list = <String>[];
    if (apiBase.trim().isNotEmpty) list.add(apiBase.trim());
    // 开发/内网联调兜底：仅在未注入地址时尝试
    if (list.isEmpty) {
      list.add('http://127.0.0.1:8080');
    }
    return list;
  }

  /// 界面展示用的数据源名称（不含任何地址）。
  static String get dataSourceLabel => hasCloud ? '云端同步' : '本地存档';
}
