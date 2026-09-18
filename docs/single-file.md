# 单文件交付机制说明

本项目每个平台只产出一个文件，双击/安装即用。这里记录每种单文件是怎么做出来的、
运行时行为是什么，方便后续维护。

## 一览

| 平台 | 产物 | 生成脚本 | 依赖 |
| --- | --- | --- | --- |
| Windows | `luoyunzong-portable.exe`（约 60MB） | `tool/windows_portable.ps1` + `tool/launcher/` | .NET SDK 8（仅构建期） |
| macOS | `luoyunzong-macos.dmg` | `tool/macos_portable.sh` | `hdiutil`（macOS 自带） |
| Linux | `luoyunzong-portable.run` | `tool/linux_portable.sh` | `tar` / `awk`（系统自带） |
| Android | `luoyunzong.apk` | `flutter build apk --release` | Flutter/Android SDK |
| iOS | `luoyunzong-unsigned.ipa` | 工作流内 `zip Payload/` | Flutter/Xcode |
| Web | `luoyunzong.html`（约 16MB） | `tool/inline_web.dart` | Dart（Flutter 自带） |

## 一、Windows：便携单文件 exe

结构（从文件头到尾）：

```
[.NET 自包含单文件启动器] [标记 <<<LUOYUNZONG_PAYLOAD_V1>>>] [发布目录 zip] [尾部索引: 魔数 + 8字节长度]
```

- 启动器源码：`tool/launcher/Program.cs`（`net8.0`，`PublishSingleFile + SelfContained`，
  用户机器**不需要**装 .NET）。
- 首次运行：通过尾部索引定位 zip → 解压到目标目录 → 启动 `luoyunzong.exe`；
  之后同一版本再次运行会跳过解压（用 `.payload.sha256` 判断载荷是否变化）。
- 解压目标目录优先级：
  1. 环境变量 `LUOYUNZONG_DIR`；
  2. exe 同级 `luoyunzong-app/`（可写时，**推荐**：整个文件夹可以随身带）；
  3. `%LOCALAPPDATA%\Luoyunzong\app`（exe 放在只读位置时）。
- 数据目录：`<解压目录>/data`（通过 `LUOYUNZONG_DATA_DIR` 传给应用），
  因此存档就在 exe 旁边，换机器拷文件夹即可。
- 自检参数：`luoyunzong-portable.exe --extract-only`（构建脚本会用它做验证）、
  `--print-target`。

> 为什么不用 7-Zip 的 SFX：`7z.sfx` 是 GUI 解压模块，不执行配置里的 `RunProgram`
> （已实测），会弹出解压对话框；而安装器模块 `7zSD.sfx` 不在官方发行包内。
> 自己编译启动器更可控，也不依赖用户装 7-Zip。

## 二、Linux：便携单文件 .run

`makeself` 同款思路，无需额外依赖：

```
[可执行 shell 脚本头] [gzip 压缩的 tar 载荷]
```

- 脚本头用 `awk` 找到 `__ARCHIVE_BELOW__` 行号，`tail -n +N` 取出载荷并 `tar -xz` 解压。
- 解压目标：`$LUOYUNZONG_DIR` → `$XDG_DATA_HOME/luoyunzong-app` → `~/.local/share/luoyunzong-app`。
- 数据目录：`<解压目录>/data`。
- 自检参数：`./luoyunzong-portable.run --extract-only`。

## 三、macOS：单文件 .dmg

`hdiutil create -format UDZO` 把 `.app` 打成压缩 DMG（单文件），构建脚本会挂载校验后再卸载。
未签名分发时，用户首次打开需右键「打开」或在「系统设置 → 隐私与安全性」放行。

## 四、Web：单文件 HTML

Flutter Web 默认会去 CDN 取 CanvasKit，并且按相对路径加载 `main.dart.js`、资源清单、字体，
所以直接把产物目录里的文件塞进一个 HTML 是不够的。`tool/inline_web.dart` 做了三件事：

1. **内联**：`main.dart.js`、`canvaskit/canvaskit.js`、`canvaskit/canvaskit.wasm`、
   `assets/**`（字体、shader、资源清单）全部 base64 内联进 HTML；
   只保留完整版 CanvasKit，丢掉 `chromium/webparagraph/skwasm/wimp` 等变体（省约 28MB）。
2. **运行时 shim**（生成在 HTML 里）：
   - 预初始化 CanvasKit：把内联的 `canvaskit.js` 用 Blob URL 动态 `import`，
     `wasm` 用内联字节 `WebAssembly.instantiate`，随后设置 `window.flutterCanvasKit`，
     Flutter loader 会直接复用它，不再按 URL 取文件；
   - 改写 `document.createElement('script').src`：把 `main.dart.js` 指到 Blob URL；
   - 拦截 `fetch` 与 `XMLHttpRequest`：`assets/**` 请求直接用内联数据应答。
3. **启动**：把 `flutter_bootstrap.js` 末尾的自动加载调用拆出来，等 CanvasKit 就绪后再
   `_flutter.loader.load({...})`（不注册 Service Worker），并带一个首帧前的加载遮罩。

结果：单个 HTML 约 16MB，**离线可用、不依赖 CDN**，放在任何子路径托管都不会白屏
（不依赖 `base href`，因为资源全部走内联拦截）。

构建：

```bash
flutter build web --release --no-web-resources-cdn   # 关键：CanvasKit 打进产物
dart run tool/inline_web.dart build/web dist/luoyunzong.html
```

验证（本地无需浏览器）：用任意静态服务器打开生成的 HTML，首帧应显示「宗门名单」页面；
CI 中会检查文件存在、包含 `LYZ_RESOURCES`、且体积大于 5MB。

## 五、常见问题

**Q：便携 exe 第一次启动稍慢？**
首次运行要解压约 25MB 载荷（几秒），之后同版本启动不再解压。

**Q：Windows 提示「未知发布者」？**
构建产物未做代码签名，SmartScreen 会拦一次；点「更多信息 → 仍要运行」即可。
配置代码签名证书后可消除。

**Q：单文件 HTML 里的数据存在哪？**
浏览器本地存储（`localStorage`）。用 `file://` 打开时部分浏览器会限制本地存储，
建议托管到 HTTP 站点，或使用桌面/手机版以获得完整的文件存档能力。
