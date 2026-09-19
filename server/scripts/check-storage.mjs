// 资源存储自检：按当前配置（数据库里的优先，其次 .env）上传一个小文件再取回。
// 用法：node scripts/check-storage.mjs
import 'dotenv/config';
import crypto from 'node:crypto';
import {
  putAsset,
  getAsset,
  storageInfo,
  reloadStorageConfig,
  currentStorageConfig,
  testStorage,
} from '../storage.mjs';
import { pool } from '../db.mjs';

async function main() {
  // 管理员在 App 里保存过的配置存在数据库，这里要先读进来
  await reloadStorageConfig();
  const info = storageInfo();
  const cfg = currentStorageConfig();
  console.log(
    `[storage] 驱动=${info.driver} 桶=${info.bucket || '(无)'} 域名=${info.domain || '(无)'} ` +
      `来源=${info.fromDatabase ? '数据库（App 里配的）' : '.env'}`,
  );
  if (info.driver === 's3') {
    console.log(`[storage] endpoint=${cfg.endpoint} region=${cfg.region}`);
  }

  // 首选走「上传→回读→清理」的探针（和 App 里的「测试连接」同一套逻辑）
  const probed = await testStorage();
  console.log(`[storage] 探针：${probed.ok ? '通过 ✅' : '失败 ❌'} ${probed.message}`);

  const bytes = crypto.randomBytes(1024);
  const id = 'probe' + Date.now().toString(36);
  const mime = 'application/octet-stream';
  const { url, driver } = await putAsset({ id, mime, bytes });
  console.log(`[storage] 上传成功: driver=${driver} url=${url || '(由服务端 /assets/' + id + ' 中转)'}`);

  const back = await getAsset({ id, mime, url });
  if (!back || back.length !== bytes.length) {
    console.error('[storage] 取回校验失败（私有桶会自动用签名请求回源）');
    process.exit(1);
  }
  console.log(`[storage] 取回校验通过（${back.length} 字节）✅`);
}

main()
  .catch((err) => {
    console.error('[storage] 失败:', err.message);
    const info = storageInfo();
    if (info.driver === 's3') {
      console.error(
        '[storage] 常见原因：\n' +
          '  1) 403 AccessDenied —— 子账户没被授权这个桶：缤纷云控制台 →「子账户&Key」→ 给子用户勾上该桶读写；\n' +
          '  2) 404 —— 桶名或 Endpoint 写错；\n' +
          '  3) 400 —— Region 不对（缤纷云是 cn-east-1）。',
      );
    }
    if (info.driver === 'upyun') {
      console.error(
        '[storage] 常见原因：又拍云上传用的是「操作员 + 操作员密码」，不是子账户 AccessKey/SecretKey；' +
          '或该操作员未被授权这个服务。',
      );
    }
    process.exit(1);
  })
  .finally(() => pool.end().catch(() => {}));
