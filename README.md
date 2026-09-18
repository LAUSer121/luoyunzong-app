# 落云宗 · 宗门管理（Flutter 多端单文件版）

由单文件网页版 `luoyunzong.html` 重建的现代化多端应用：**一套 Dart 代码**，产出
Windows / macOS / Linux 桌面程序、Android / iOS 手机应用，以及**单个 HTML 网页版**。

- 🎨 现代 Material 3 界面：深空青金配色、响应式布局（宽屏侧边导航 / 窄屏底部导航 + 抽屉）
- 🧩 功能对齐旧版：宗门名单、宗门任务、通天塔榜单、山峰、宗门排行榜、成绩导入、公告、更新内容
- 📄 **单文件交付**：每个平台只产出一个文件，双击即用（网页版也是单个 HTML）
- 🈶 中文字形修正：显式指定中文无衬线/楷体字体栈，避免回退到日文字形（「点」被画成竖画）
- 💾 数据层抽象：默认本地存储（单文件存档），预留 HTTP + MySQL 接口实现，切换只需改一行配置
- 🔁 兼容旧存档：可直接导入旧版 `落云宗存档.js` / `.json`
- ⚙️ GitHub Actions：多端并行构建，每个平台产出一个单文件制品

---

## 一、单文件产物一览

| 平台 | 产物（单文件） | 使用方式 | 数据位置 |
| --- | --- | --- | --- |
| Windows | `luoyunzong-portable.exe` | 双击即用：首次运行解压到 `luoyunzong-app/` 并启动 | `luoyunzong-app/data/`（随文件夹一起搬走） |
| macOS | `luoyunzong-macos.dmg` | 双击挂载，把 App 拖进「应用程序」 | `~/Library/Application Support/...` |
| Linux | `luoyunzong-portable.run` | `chmod +x` 后 `./luoyunzong-portable.run`，自解压再启动 | `~/.local/share/luoyunzong-app/data` |
| Android | `luoyunzong.apk` | 手机上直接安装 | 应用私有目录 |
| iOS | `luoyunzong-unsigned.ipa` | 需自签 / 侧载（AltStore、Xcode 等） | 应用沙盒 |
| 网页版 | `luoyunzong.html` | **单个 HTML**（约 16MB）：双击用浏览器打开即用，也可放到任意静态托管 | 浏览器本地存储 |

> 网页版单文件把 `main.dart.js`、CanvasKit 的 JS/WASM、字体与资源清单全部内联，
> 并用运行时 shim 接管加载（`tool/inline_web.dart`），因此**不依赖 CDN、可离线运行**，
> 也不会出现托管在子路径时的白屏问题。

## 二、快速开始（本地开发）

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
flutter devices            # 查看手机设备后：flutter run -d <device_id>
```

> **Windows 本地开发注意**：工程路径里**不要带空格**。带空格的路径（例如 `D:\Deepseek Harness\...`）
> 会让 Flutter 的 native assets 构建钩子拼出未加引号的命令行，
> 报 `'D:\Deepseek' 不是内部或外部命令`，`flutter test` / `flutter build` 会失败。
> 解决方式：把工程放到无空格路径（如 `D:\dev\luoyunzong_app`）；
> GitHub Actions 上的路径本身无空格，CI 不受影响。

## 三、本地打包（生成单文件）

```bash
# Windows：单文件便携版 exe（需要 .NET SDK 8，用来编译自带启动器）
flutter build windows --release
pwsh -File tool/windows_portable.ps1          # → dist/luoyunzong-portable.exe

# Linux：单文件 .run
flutter build linux --release
bash tool/linux_portable.sh                    # → dist/luoyunzong-portable.run

# macOS：单文件 .dmg
flutter build macos --release
bash tool/macos_portable.sh                    # → dist/luoyunzong-macos.dmg

# Web：单文件 html
flutter build web --release --no-web-resources-cdn
dart run tool/inline_web.dart build/web dist/luoyunzong.html
```

本地自检（与 CI 一致）：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## 四、GitHub Actions

推送到 `main` 触发两条工作流：

| 工作流 | 产出 |
| --- | --- |
| `Analyze & Test` | 格式校验 → 静态检查 → 单元/组件测试（38 个用例） |
| `Build (All Platforms)` | 六个单文件制品：便携 exe / dmg / run / apk / ipa / 单文件 html |

打 `v*` 标签（`git tag v1.0.0 && git push --tags`）会把六个单文件制品发布为 GitHub Release，
并附带 `SHA256SUMS.txt`；`Web (GitHub Pages)` 工作流还会把网页版部署成可访问的网址。

> iOS 正式分发需要 Apple 开发者证书：配置 `IOS_CERTIFICATE_P12`、`IOS_CERTIFICATE_PASSWORD`、
> `IOS_PROVISIONING_PROFILE` 等 Secrets 后，把 `--no-codesign` 换成正式签名步骤；
> Android 发布包同理配置 `ANDROID_KEYSTORE_*` Secrets。

## 五、目录结构

```
lib/
├─ main.dart                 入口：初始化存储与状态，启动应用
├─ app.dart                  MaterialApp / 主题 / 响应式外壳
├─ core/                     常量、主题（含中文字体栈）、解析与图像工具
├─ domain/                   领域模型、派生统计（榜单/成绩）与仓储抽象
├─ data/                     本地存储、HTTP(MySQL) 仓储、存档编解码、XLSX 解析
├─ state/                    AppState（单一数据源 + 自动保存）与 BGM 控制器
├─ features/                 名单/任务/通天塔/山峰/排行榜/成绩/公告/设置
└─ widgets/                  共享组件：徽章、头像、卡片、对话框、成绩走势图
tool/
├─ windows_portable.ps1      Windows 单文件便携 exe 打包
├─ launcher/                 .NET 便携启动器源码（自解压 + 启动 + 数据目录）
├─ linux_portable.sh         Linux 单文件 .run 打包
├─ macos_portable.sh         macOS 单文件 .dmg 打包
└─ inline_web.dart           Web 产物内联为单个 HTML
```

详见 [`docs/architecture.md`](docs/architecture.md)、[`docs/legacy-feature-map.md`](docs/legacy-feature-map.md)、
[`docs/backend-mysql.md`](docs/backend-mysql.md)。

## 六、数据与后端演进

| 阶段 | 存储 | 说明 |
| --- | --- | --- |
| 现在 | 本地文件 / 浏览器存储 | `LocalRepository`，自动保存 + 导入导出存档（与旧版格式互通） |
| 下一步 | HTTP + MySQL | `ApiRepository` + `ApiClient`，表结构与参考服务端见 `docs/backend-mysql.md` |

便携版数据目录规则（桌面端）：环境变量 `LUOYUNZONG_DATA_DIR` → 可执行文件同级 `luoyunzong_data/`
→ 系统应用支持目录，三者依次回退。

## 七、旧版数据迁移

1. 在旧网页点「导出存档」，得到 `落云宗存档.js`（或 `落云宗存档.json`）。
2. 新应用「设置 → 存档 → 导入存档」，选择该文件。
3. 成员、山峰、通天塔、成绩场次、BGM 曲单、背景与管理员密码会全部迁移。

## 八、许可

内部使用项目，未附开源许可。
