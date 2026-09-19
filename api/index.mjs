// Vercel Serverless 入口：把 Express app 当 handler 用（不监听端口）。
//
// 说明：
//  - 冷启动时先把数据库里的存储配置/上传上限读进来（warmup），
//    之后同一个实例里的请求直接复用内存缓存；
//  - 函数请求体上限 4.5MB，所以大文件（视频）必须走 /api/assets/sign
//    预签名直传缤纷云，字节不经过这里；
//  - 数据库用 Aiven（公网可达），资源用缤纷云，实例本身无状态。
import app, { warmup } from '../server/index.mjs';

let warmed = null;

export default async function handler(req, res) {
  if (!warmed) warmed = warmup();
  try {
    await warmed;
  } catch {
    // 配置读不到也让请求继续（接口自己会回落到 .env / 默认值）
  }
  return app(req, res);
}
