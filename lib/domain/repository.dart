/// 仓储抽象：数据层契约。
///
/// 目前提供两种实现：
/// - `LocalRepository`：本地文件 / 浏览器存储（默认）
/// - `ApiRepository`：HTTP + MySQL 服务端（后期接入，见 docs/backend-mysql.md）
library;

import 'models.dart';

abstract class LuoyunRepository {
  /// 读取存档；不存在返回 `null`。
  Future<Archive?> load();

  /// 覆盖写入存档。
  Future<void> save(Archive archive);

  /// 清空存档。
  Future<void> clear();

  /// 外部变更通知（如服务端推送、多窗口写入）。本地实现默认不发事件。
  Stream<void> get changes;

  /// 仓储标识，用于界面展示当前数据源。
  String get label;
}
