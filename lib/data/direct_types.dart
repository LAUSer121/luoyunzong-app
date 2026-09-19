/// 直连模式共用的小类型（Web/桌面都能编译）。
library;

/// MySQL 连接参数（打包时用 --dart-define 注入，和令牌一样不进仓库）。
class DbConfig {
  const DbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
    this.orgId = 'default',
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String database;
  final String orgId;

  bool get isComplete =>
      host.isNotEmpty && user.isNotEmpty && database.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'user': user,
    'password': password,
    'database': database,
    'orgId': orgId,
  };

  factory DbConfig.fromJson(Map<String, Object?> json) => DbConfig(
    host: '${json['host'] ?? ''}',
    port: (json['port'] as num?)?.toInt() ?? 23483,
    user: '${json['user'] ?? ''}',
    password: '${json['password'] ?? ''}',
    database: '${json['database'] ?? 'defaultdb'}',
    orgId: '${json['orgId'] ?? 'default'}',
  );
}
