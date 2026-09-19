/// 直连模式的门面：按平台选择实现。
///
/// - 桌面 / 手机（有 dart:io）：direct_repository_io.dart，真连 MySQL + 缤纷云；
/// - Web（浏览器）：direct_repository_stub.dart，只保留接口
///   （浏览器开不了原始 TCP，直连在 Web 上不启用）。
///
/// 这样 mysql_client（依赖 dart:io）不会进入 Web 构建，单文件网页版照常编译。
library;

export 'direct_repository_io.dart'
    if (dart.library.js_interop) 'direct_repository_stub.dart';
export 'direct_types.dart' show DbConfig;
export 's3_client.dart' show S3Client, S3Config, S3Exception;
