// 腾讯云 CloudBase（云开发）云函数入口。
//
// 为什么用 CommonJS + 动态 import：
//   CloudBase 的函数入口认 `exports.main`，而我们的服务端是 ESM（.mjs）。
//   这里用动态 import 把 ESM 的 Express app 拉进来，再用 serverless-http
//   把「API 网关事件」翻译成普通的 http 请求 → Express 照常路由。
//
// 冷启动时先 warmup()（读数据库里的存储配置/上传上限），之后实例内复用。
const serverless = require('serverless-http');

let handlerPromise = null;

function getHandler() {
  if (!handlerPromise) {
    handlerPromise = (async () => {
      const mod = await import('./server/index.mjs');
      try {
        await mod.warmup();
      } catch (e) {
        console.error('[cloudbase] warmup 失败（接口会回落到默认配置）:', e.message);
      }
      return serverless(mod.default);
    })();
  }
  return handlerPromise;
}

exports.main = async (event, context) => {
  const handler = await getHandler();
  // 让 serverless-http 知道真实路径（CloudBase 的 HTTP 访问服务会带 path）
  return handler(event, context);
};
