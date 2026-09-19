// 资源存储自检：按当前 STORAGE_DRIVER 上传一个小文件再取回。
// 用法：node scripts/check-storage.mjs
import 'dotenv/config';
import crypto from 'node:crypto';
import { putAsset, getAsset, storageInfo } from '../storage.mjs';

async function main() {
  const info = storageInfo();
  console.log(`[storage] 驱动=${info.driver} 桶=${info.bucket || '(无)'} 域名=${info.domain || '(无)'}`);

  const bytes = crypto.randomBytes(1024);
  const id = 'probe' + Date.now().toString(36);
  const mime = 'application/octet-stream';

  const { url, driver } = await putAsset({ id, mime, bytes });
  console.log(`[storage] 上传成功: driver=${driver} url=${url || '(本地 /assets/' + id + ')'}`);

  const back = await getAsset({ id, mime, url });
  if (!back || back.length !== bytes.length) {
    console.error('[storage] 取回校验失败');
    process.exit(1);
  }
  console.log(`[storage] 取回校验通过（${back.length} 字节）✅`);
  if (info.driver === 'upyun') {
    console.log('[storage] 提示：又拍云需要在控制台把该操作员授权到服务，且绑定访问域名（UPYUN_DOMAIN）。');
  }
}

main().catch((err) => {
  console.error('[storage] 失败:', err.message);
  if (storageInfo().driver === 'upyun') {
    console.error(
      '[storage] 常见原因：UPYUN_OPERATOR / UPYUN_PASSWORD 未填——存储上传用的是「操作员 + 密码」，' +
        '不是子账户 AccessKey/SecretKey；或该操作员未被授权这个服务。',
    );
  }
  process.exit(1);
});
