// 把 Flutter Web 产物（build/web）打包成「单个 HTML 文件」。
//
// 原理：把 main.dart.js、canvaskit.js/wasm、assets/** 等资源全部内联进 HTML，
// 再用一段 shim 拦截运行时加载：
//   1) 预初始化 CanvasKit（内联的 JS + WASM 通过 Blob URL 动态 import），
//      使 Flutter loader 直接复用 window.flutterCanvasKit，不再按 URL 取文件；
//   2) 重写 document.createElement('script').src，把 main.dart.js 指到 Blob URL；
//   3) 拦截 fetch / XMLHttpRequest，把 assets/** 请求用内联数据直接应答。
//
// 用法：dart run tool/inline_web.dart [webDir] [outFile]
//   webDir  默认 build/web
//   outFile 默认 dist/luoyunzong.html

import 'dart:convert';
import 'dart:io';

const String _kPayloadMarker = '_flutter.loader.load({';

Future<void> main(List<String> args) async {
  final String webDir = args.isNotEmpty ? args[0] : 'build/web';
  final String outFile = args.length > 1 ? args[1] : 'dist/luoyunzong.html';

  final Directory dir = Directory(webDir);
  if (!dir.existsSync()) {
    stderr.writeln(
      '[inline] 未找到 Web 产物目录：$webDir（请先 flutter build web --release --no-web-resources-cdn）',
    );
    exit(1);
  }

  // ------------------------------------------------------------------
  // 1) 收集资源
  // ------------------------------------------------------------------
  final Map<String, List<int>> resources = <String, List<int>>{};
  for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String rel = entity.path
        .substring(dir.path.length + 1)
        .replaceAll(r'\', '/');
    if (rel == 'index.html') continue;
    if (rel.endsWith('.map') ||
        rel.endsWith('.symbols') ||
        rel.endsWith('.last_build_id')) {
      continue; // 调试文件、构建标记不需要内联
    }
    // 只保留运行时真正会加载的 CanvasKit 变体（完整版），其余变体动辄 20MB+。
    if (rel.startsWith('canvaskit/')) {
      const List<String> neededCanvasKit = <String>[
        'canvaskit/canvaskit.js',
        'canvaskit/canvaskit.wasm',
      ];
      if (!neededCanvasKit.contains(rel)) continue;
    }
    if (!(rel == 'main.dart.js' ||
        rel == 'flutter_bootstrap.js' ||
        rel.startsWith('canvaskit/') ||
        rel.startsWith('assets/'))) {
      continue;
    }
    resources[rel] = entity.readAsBytesSync();
  }

  for (final String required in <String>[
    'main.dart.js',
    'flutter_bootstrap.js',
    'canvaskit/canvaskit.js',
    'canvaskit/canvaskit.wasm',
    'assets/AssetManifest.bin',
    'assets/FontManifest.json',
  ]) {
    if (!resources.containsKey(required)) {
      stderr.writeln('[inline] 缺少必需资源：$required');
      exit(1);
    }
  }

  // ------------------------------------------------------------------
  // 2) 准备内联数据
  // ------------------------------------------------------------------
  final Map<String, Map<String, String>> table =
      <String, Map<String, String>>{};
  for (final MapEntry<String, List<int>> e in resources.entries) {
    if (e.key == 'flutter_bootstrap.js') continue; // 作为脚本内联，不进资源表
    table[e.key] = <String, String>{
      'b': base64Encode(e.value),
      'm': _mimeOf(e.key),
    };
  }

  final String bootstrap = utf8.decode(resources['flutter_bootstrap.js']!);
  final int splitIndex = bootstrap.indexOf(_kPayloadMarker);
  if (splitIndex < 0) {
    stderr.writeln(
      '[inline] flutter_bootstrap.js 结构不符合预期（未找到 load 调用），请检查 Flutter 版本',
    );
    exit(1);
  }
  final String bootstrapHead = bootstrap.substring(0, splitIndex);

  final String originalIndex = File('${dir.path}/index.html')
      .readAsStringSync();
  final String bodyMarkup = _extractBody(originalIndex);

  // ------------------------------------------------------------------
  // 3) 生成单文件 HTML
  // ------------------------------------------------------------------
  final StringBuffer html = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="zh-CN">')
    ..writeln('<head>')
    ..writeln('<meta charset="UTF-8">')
    ..writeln('<meta content="IE=Edge" http-equiv="X-UA-Compatible">')
    ..writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">',
    )
    ..writeln('<meta name="description" content="落云宗 · 宗门管理（单文件便携网页版）">')
    ..writeln('<meta name="apple-mobile-web-app-capable" content="yes">')
    ..writeln('<title>落云宗 · 宗门管理</title>')
    ..writeln('<style>')
    ..writeln(_kStyle)
    ..writeln('</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('  <div id="lyz-boot">')
    ..writeln('    <div class="lyz-title">落云宗</div>')
    ..writeln('    <div class="lyz-sub">宗门管理 · 正在载入…</div>')
    ..writeln('  </div>')
    ..writeln(bodyMarkup)
    ..writeln('  <!-- 内联资源表（base64） -->')
    ..writeln('  <script>window.LYZ_RESOURCES = ${jsonEncode(table)};</script>')
    ..writeln('  <!-- 运行时拦截 shim -->')
    ..writeln('  <script>')
    ..writeln(_kShim)
    ..writeln('</script>')
    ..writeln('  <!-- Flutter loader（flutter_bootstrap.js 去掉自动加载调用） -->')
    ..writeln('  <script>')
    ..writeln(bootstrapHead)
    ..writeln('</script>')
    ..writeln('  <!-- 启动：先初始化 CanvasKit，再交给 loader -->')
    ..writeln('  <script>')
    ..writeln(_kBoot)
    ..writeln('</script>')
    ..writeln('</body>')
    ..writeln('</html>');

  final File out = File(outFile);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(html.toString());

  final double sizeMb = out.lengthSync() / 1024 / 1024;
  stdout.writeln(
    '[inline] 生成：${out.path}（${sizeMb.toStringAsFixed(1)} MB，内联 ${table.length} 个资源）',
  );
}

String _extractBody(String indexHtml) {
  final RegExpMatch? match = RegExp(
    r'<body[^>]*>(.*?)</body>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(indexHtml);
  String body = match?.group(1) ?? '';
  // 去掉原来的 bootstrap script 标签（我们改为内联）
  body = body.replaceAll(
    RegExp(
      r'<script[^>]*flutter_bootstrap\.js[^>]*>\s*</script>',
      caseSensitive: false,
    ),
    '',
  );
  return body.trim();
}

String _mimeOf(String path) {
  if (path.endsWith('.js')) return 'text/javascript';
  if (path.endsWith('.wasm')) return 'application/wasm';
  if (path.endsWith('.json') ||
      path.endsWith('.bin') ||
      path.endsWith('.bin.json')) {
    return 'application/json';
  }
  if (path.endsWith('.otf')) return 'font/otf';
  if (path.endsWith('.ttf')) return 'font/ttf';
  if (path.endsWith('.frag')) return 'application/octet-stream';
  if (path.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

const String _kStyle = r'''
html, body { margin: 0; padding: 0; height: 100%; background: #070D1C; color: #F3EAD6; }
#lyz-boot {
  position: fixed; inset: 0; display: flex; flex-direction: column; gap: 10px;
  align-items: center; justify-content: center; z-index: 9999;
  background: radial-gradient(circle at 30% 20%, #12203c, #070D1C 70%);
  transition: opacity .4s ease;
}
#lyz-boot.hide { opacity: 0; pointer-events: none; }
#lyz-boot .lyz-title { font-size: 32px; letter-spacing: 10px; color: #F7E2A8; }
#lyz-boot .lyz-sub { font-size: 13px; letter-spacing: 3px; color: #8F8FA8; }
''';

const String _kShim = r'''
(function () {
  var RES = window.LYZ_RESOURCES || {};
  var blobCache = {};

  function b64ToBytes(b64) {
    var bin = atob(b64);
    var len = bin.length;
    var out = new Uint8Array(len);
    for (var i = 0; i < len; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function b64ToText(b64) {
    try { return new TextDecoder('utf-8').decode(b64ToBytes(b64)); }
    catch (e) { return atob(b64); }
  }
  function blobUrlFor(key, mime) {
    if (!blobCache[key]) {
      var bytes = b64ToBytes(RES[key].b);
      blobCache[key] = URL.createObjectURL(new Blob([bytes], { type: mime || RES[key].m }));
    }
    return blobCache[key];
  }
  // 把任意 URL 归一化成资源表里的相对路径（兼容子路径部署与 file://）
  function normalize(url) {
    if (!url) return '';
    var path = String(url);
    try {
      var u = new URL(path, document.baseURI);
      path = u.pathname;
    } catch (e) { /* 保持原样 */ }
    path = path.replace(/^\.?\//, '');
    if (RES[path]) return path;
    for (var key in RES) {
      if (path === key || path.endsWith('/' + key)) return key;
    }
    return path;
  }
  window.__lyzNormalize = normalize;

  // ---- fetch 拦截 ----
  var origFetch = window.fetch ? window.fetch.bind(window) : null;
  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : (input && input.url);
    var key = normalize(url);
    if (RES[key]) {
      return Promise.resolve(new Response(b64ToBytes(RES[key].b), {
        status: 200,
        headers: { 'Content-Type': RES[key].m }
      }));
    }
    return origFetch ? origFetch(input, init) : Promise.reject(new Error('resource not found: ' + url));
  };

  // ---- XHR 拦截 ----
  var OrigOpen = XMLHttpRequest.prototype.open;
  var OrigSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__lyzKey = normalize(url);
    return OrigOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    var key = this.__lyzKey;
    if (!key || !RES[key]) return OrigSend.apply(this, arguments);
    var xhr = this;
    var bytes = b64ToBytes(RES[key].b);
    var type = RES[key].m;
    setTimeout(function () {
      try {
        Object.defineProperty(xhr, 'status', { value: 200, configurable: true });
        Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
        Object.defineProperty(xhr, 'responseURL', { value: key, configurable: true });
        var body = (xhr.responseType === 'arraybuffer') ? bytes.buffer
          : (xhr.responseType === 'blob') ? new Blob([bytes], { type: type })
          : b64ToText(RES[key].b);
        Object.defineProperty(xhr, 'response', { value: body, configurable: true });
        Object.defineProperty(xhr, 'responseText', { value: b64ToText(RES[key].b), configurable: true });
      } catch (e) { /* 只读属性在部分浏览器上不可改，忽略 */ }
      if (typeof xhr.onreadystatechange === 'function') xhr.onreadystatechange();
      if (typeof xhr.onload === 'function') xhr.onload();
      try { xhr.dispatchEvent(new Event('load')); xhr.dispatchEvent(new Event('loadend')); } catch (e) {}
    }, 0);
  };

  // ---- script.src 重写：main.dart.js 等改用 Blob URL ----
  var origCreateElement = document.createElement.bind(document);
  document.createElement = function (name, options) {
    var el = origCreateElement(name, options);
    if (String(name).toLowerCase() === 'script') {
      var realSrc = '';
      try {
        Object.defineProperty(el, 'src', {
          configurable: true,
          get: function () { return realSrc; },
          set: function (value) {
            var key = normalize(value);
            realSrc = RES[key] ? blobUrlFor(key, 'text/javascript') : value;
            el.setAttribute('src', realSrc);
          }
        });
      } catch (e) { /* 浏览器不支持时退回默认行为 */ }
    }
    return el;
  };

  // ---- 预初始化 CanvasKit：loader 会直接复用 window.flutterCanvasKit ----
  window.__lyzInitCanvasKit = function () {
    if (window.flutterCanvasKit) return Promise.resolve(window.flutterCanvasKit);
    if (!RES['canvaskit/canvaskit.js'] || !RES['canvaskit/canvaskit.wasm']) {
      return Promise.reject(new Error('缺少 CanvasKit 资源'));
    }
    var jsUrl = blobUrlFor('canvaskit/canvaskit.js', 'text/javascript');
    var wasmBytes = b64ToBytes(RES['canvaskit/canvaskit.wasm'].b);
    return import(jsUrl).then(function (mod) {
      var factory = mod.default || mod.CanvasKitInit || window.CanvasKitInit;
      return factory({
        instantiateWasm: function (imports, successCallback) {
          WebAssembly.instantiate(wasmBytes, imports).then(function (result) {
            successCallback(result.instance, result.module);
          }).catch(function (err) {
            console.error('[lyz] wasm 实例化失败', err);
          });
          return {};
        },
        locateFile: function (path) { return path; }
      }).then(function (canvasKit) {
        window.flutterCanvasKit = canvasKit;
        return canvasKit;
      });
    });
  };
})();
''';

const String _kBoot = r'''
(function () {
  function hideBoot() {
    var el = document.getElementById('lyz-boot');
    if (!el) return;
    el.classList.add('hide');
    setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 600);
  }
  window.addEventListener('flutter-first-frame', hideBoot);
  setTimeout(hideBoot, 15000); // 兜底：即使事件未触发也不遮挡界面

  window.__lyzInitCanvasKit().catch(function (err) {
    console.error('[lyz] CanvasKit 预初始化失败，回退默认加载流程', err);
  }).then(function () {
    try {
      window._flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit' } });
    } catch (e) {
      console.error('[lyz] Flutter loader 启动失败', e);
    }
  });
})();
''';
