# 落云宗 · 宗门管理（Flutter 多端版）

由单文件网页版 `luoyunzong.html` 重建的现代化多端应用：**一套 Dart 代码**，同时产出
Windows / macOS / Linux 桌面程序、Android / iOS 手机应用与 Web 页面。

- 🎨 现代 Material 3 界面：深空青金配色、响应式布局（宽屏侧边导航 / 窄屏底部导航）
- 🧩 功能对齐旧版：宗门名单、宗门任务、通天塔榜单、山峰、宗门排行榜、成绩导入、公告、更新内容
- 💾 数据层抽象：默认本地存储（单文件存档），预留 HTTP + MySQL 接口实现，切换只需改一行配置
- 🔁 兼容旧存档：可直接导入旧版 `落云宗存档.js` / `.json`
- ⚙️ GitHub Actions 多端编译：见 [`.github/workflows/build.yml`](.github/workflows/build.yml)

---

## 一、快速开始（本地开发）

```bash
# 1) 安装 Flutter（stable 3.47+）：https://docs.flutter.dev/get-started/install
flutter --version

# 2) 拉依赖
flutter pub get

# 3) 运行（任选其一）
flutter run -d windows     # Windows 桌面
flutter run -d macos       # macOS 桌面
flutter run -d linux       # Linux 桌面
flutter run -d chrome      # Web（浏览器）
flutter devices            # 查看手机设备后：flutter run -d <device-id>
```

## 二、打包发布

```bash
flutter build windows --release     # build/windows/x64/runner/Release/
flutter build macos   --release     # build/macos/Build/Products/Release/*.app
flutter build linux   --release     # build/linux/x64/release/bundle/
flutter build apk     --release --split-per-abi
flutter build appbundle --release
flutter build ios     --release --no-codesign
flutter build web     --release     # build/web/
```

推送到 `main` 分支会触发全平台构建；打 `v*` 标签（如 `git tag v1.0.0 && git push --tags`）
会额外把 APK / AAB / 桌面压缩包 / Web 产物发布为 GitHub Release，并生成 `SHA256SUMS.txt`。

> iOS 正式分发需要 Apple 开发者证书：在仓库 Secrets 中配置
> `IOS_CERTIFICATE_P12`、`IOS_CERTIFICATE_PASSWORD`、`IOS_PROVISIONING_PROFILE` 后，
> 把工作流中的 `--no-codesign` 换成正式签名步骤即可。Android 发布包同理配置
> `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。

## 三、目录结构

```
lib/
├─ main.dart                 入口：初始化存储与状态，启动应用
├─ app.dart                  MaterialApp / 主题 / 响应式外壳
├─ core/                     常量（职务、境界、任务条件）、主题、工具函数
├─ domain/                   领域模型 + 仓储抽象接口（数据层契约）
├─ data/                     本地存储实现、HTTP(MySQL) 实现、存档编解码
├─ state/                    AppState（单一数据源 + 自动保存）
├─ features/                 各功能页：名单/任务/通天塔/山峰/排行榜/成绩/公告/设置
└─ widgets/                  共享组件：徽章、头像、卡片、对话框、图表
```

详见 [`docs/architecture.md`](docs/architecture.md) 与 [`docs/legacy-feature-map.md`](docs/legacy-feature-map.md)。

## 四、数据与后端演进

| 阶段 | 存储 | 说明 |
| --- | --- | --- |
| 现在 | 本地文件 / 浏览器存储 | `LocalRepository`，自动保存 + 导入导出存档（与旧版格式互通） |
| 下一步 | HTTP + MySQL | `ApiRepository` + `lib/data/api_client.dart`，服务端表结构见 `docs/backend-mysql.md` |

切换方式：`main.dart` 中选择仓储实现，或运行时通过设置页配置服务端地址。

## 五、旧版数据迁移

1. 在旧网页点「导出存档」，得到 `落云宗存档.js`（或 `落云宗存档.json`）。
2. 新应用「设置 → 存档 → 导入存档」，选择该文件。
3. 成员、山峰、通天塔、成绩场次、BGM 曲单、背景与管理员密码会全部迁移。

## 六、许可

内部使用项目，未附开源许可。
