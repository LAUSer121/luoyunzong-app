# 架构说明

## 1. 分层

```
┌──────────────────────────────────────────────────────────┐
│ features/*  (UI 页面与局部组件，只依赖 AppState 与模型)   │
├──────────────────────────────────────────────────────────┤
│ state/AppState  (ChangeNotifier：唯一可变状态 + 业务动作) │
├──────────────────────────────────────────────────────────┤
│ data/  LocalRepository │ ApiRepository   (仓储实现)       │
│        archive_codec   (旧存档 JSON ⇄ Archive)            │
├──────────────────────────────────────────────────────────┤
│ domain/  models.dart + repository.dart  (纯 Dart，无依赖) │
└──────────────────────────────────────────────────────────┘
```

- **domain** 不 import Flutter，可在任意平台与单元测试中使用。
- **data** 只负责「存取 + 序列化」，不含业务规则。
- **state** 是唯一可变状态源；所有页面通过 `context.watch<AppState>()` 读，通过方法改。
- **features** 不直接读写存储，也不直接序列化 JSON。

## 2. 状态与持久化流程

```
用户操作 → AppState.mutate() → notifyListeners() → 界面重建
                          └─→ 防抖 800ms → repository.save(archive)
```

- 存储失败（如磁盘满）会通过 `AppState.lastError` 暴露给设置页提示。
- 「管理员解锁」是会话态（`bool unlocked`），不落盘；明文密码沿用旧版语义
  （存档内 `adminPassword`），仅在受控的本地场景使用，后续接 MySQL 时可换成服务端校验。

## 3. 数据层契约

`domain/repository.dart`：

```dart
abstract class LuoyunRepository {
  Future<Archive?> load();          // 无存档返回 null
  Future<void> save(Archive a);
  Future<void> clear();
  Stream<void> get changes;         // 可选：多端同步时的外部变更通知
}
```

- `LocalRepository`：桌面/移动端写 `应用支持目录/luoyunzong_archive.json`；Web 端回退到
  `shared_preferences`（localStorage）。两者使用同一份 JSON，可与旧版存档互换。
- `ApiRepository`：同一接口的 HTTP 实现，端点约定见 `docs/backend-mysql.md`，
  服务端按 MySQL 存储；客户端只需把 `main.dart` 的仓储实现换掉。

## 4. 平台差异处理

| 能力 | 桌面 | 移动 | Web |
| --- | --- | --- | --- |
| 存档文件读写 | 文件系统 | 文件系统 | localStorage |
| 导入导出 | 文件选择/保存 | 文件选择/分享 | 浏览器下载/上传 |
| 立绘与视频 | 支持 | 支持 | 支持（浏览器解码） |
| BGM | 支持 | 支持 | 浏览器自动播放策略限制，需用户首次点击 |

统一通过 `core/platform.dart` 中的 `StorageBackend` / `isDesktop` / `isWeb` 判断，
业务代码不散落 `Platform.isX`。

## 5. 界面组织

- 外壳 `AppShell`：≥ 900px 用 `NavigationRail`（左侧栏，含管理解锁区），
  < 900px 用 `NavigationBar`（底部）+ 顶部 AppBar 抽屉入口。
- 每个功能页是独立 `StatefulWidget`，负责自己的筛选/选择等**页面局部态**；
  跨页共享的数据一律来自 `AppState`。
- 视觉规范集中在 `core/theme.dart`：深空底 `#0B1226`、面板 `#1B2030`、
  主金 `#F7E2A8`、暗金 `#D4B886`、玉青 `#7DFF9E`、警示 `#FF8A8A`、弱化文字 `#8F8FA8`。

## 6. 测试策略

- `test/` 覆盖纯逻辑：批量名单解析、成绩解析、分数段统计、两场对比、境界排序、
  旧存档编解码与迁移。UI 用 widget test 覆盖关键页面能渲染出空态与数据态。
- CI 中 `flutter analyze` + `flutter test` 作为所有平台构建的前置门禁。
