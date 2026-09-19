// 资源存储驱动：local（服务器磁盘） / upyun（又拍云对象存储） / s3（R2、MinIO 等兼容 S3）
//
// 客户端只认「资源 id」；存哪由这里决定：
//   - local：落盘 uploads/<id>，由本服务用 /assets/<id> 提供访问
//   - upyun：直传又拍云，返回 <UPYUN_DOMAIN>/<path>
//   - s3：SigV4 直传（不引第三方 SDK）
import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DRIVER = (process.env.STORAGE_DRIVER || 'local').toLowerCase();
const UPLOAD_DIR = fileURLToPath(new URL('uploads/', import.meta.url));

export const storageInfo = () => ({
  driver: DRIVER,
  bucket: DRIVER === 'upyun' ? process.env.UPYUN_BUCKET : process.env.S3_BUCKET,
  domain: DRIVER === 'upyun' ? process.env.UPYUN_DOMAIN : process.env.S3_PUBLIC_BASE,
});

const extOf = (mime) =>
  ({
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
  })[mime] || 'bin';

const keyOf = (id, mime) => `luoyunzong/${id}.${extOf(mime)}`;

/**
 * 保存资源；返回 { url, driver }。url 为空表示由本服务 /assets/<id> 提供。
 */
export async function putAsset({ id, mime, bytes }) {
  if (DRIVER === 'upyun') {
    const url = await putUpyun({ id, mime, bytes });
    return { url, driver: 'upyun' };
  }
  if (DRIVER === 's3') {
    const url = await putS3({ id, mime, bytes });
    return { url, driver: 's3' };
  }
  await fs.mkdir(UPLOAD_DIR, { recursive: true });
  await fs.writeFile(path.join(UPLOAD_DIR, `${id}.${extOf(mime)}`), bytes);
  return { url: '', driver: 'local' };
}

/** 取资源字节：本地读盘；对象存储则按 URL 回源。 */
export async function getAsset({ id, mime, url }) {
  if (!url) {
    const file = path.join(UPLOAD_DIR, `${id}.${extOf(mime)}`);
    try {
      return await fs.readFile(file);
    } catch {
      return null;
    }
  }
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return Buffer.from(await res.arrayBuffer());
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// 又拍云：REST API
//   PUT http://v0.api.upyun.com/<bucket>/<path>
//   Authorization: UPYUN <operator>:<signature>
//   signature = md5(`METHOD&PATH&DATE&CONTENT_LENGTH&md5(PASSWORD)`)
//   也支持 Authorization: Basic base64(operator:password)
// 说明：AccessKey/SecretKey 是「子账户 Key」，用于管理类接口（刷新缓存等）；
//       存储上传需要服务绑定的「操作员」及其密码（控制台可设置/重置）。
// ---------------------------------------------------------------------------
async function putUpyun({ id, mime, bytes }) {
  const bucket = process.env.UPYUN_BUCKET;
  const operator = process.env.UPYUN_OPERATOR;
  const password = process.env.UPYUN_PASSWORD;
  if (!bucket || !operator || !password) {
    throw new Error('又拍云配置不完整：需要 UPYUN_BUCKET / UPYUN_OPERATOR / UPYUN_PASSWORD');
  }
  const uriPath = `/${bucket}/${keyOf(id, mime)}`;
  const date = new Date().toUTCString();
  const md5Password = crypto.createHash('md5').update(password).digest('hex');
  const signature = crypto
    .createHash('md5')
    .update(`PUT&${uriPath}&${date}&${bytes.length}&${md5Password}`)
    .digest('hex');

  const res = await fetch(`https://v0.api.upyun.com${uriPath}`, {
    method: 'PUT',
    headers: {
      Authorization: `UPYUN ${operator}:${signature}`,
      Date: date,
      'Content-Type': mime,
      'Content-Length': String(bytes.length),
    },
    body: bytes,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`又拍云上传失败 ${res.status} ${text.slice(0, 200)}`);
  }
  const domain = (process.env.UPYUN_DOMAIN || '').replace(/\/+$/, '');
  return domain ? `${domain}/${keyOf(id, mime)}` : '';
}

// ---------------------------------------------------------------------------
// S3 / Cloudflare R2 / MinIO：手写 SigV4（避免引入 aws-sdk）
// ---------------------------------------------------------------------------
async function putS3({ id, mime, bytes }) {
  const endpoint = (process.env.S3_ENDPOINT || '').replace(/\/+$/, '');
  const bucket = process.env.S3_BUCKET;
  const region = process.env.S3_REGION || 'auto';
  const accessKey = process.env.S3_ACCESS_KEY_ID;
  const secretKey = process.env.S3_SECRET_ACCESS_KEY;
  if (!endpoint || !bucket || !accessKey || !secretKey) {
    throw new Error('S3 配置不完整：需要 S3_ENDPOINT / S3_BUCKET / S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY');
  }
  const key = keyOf(id, mime);
  const url = new URL(`${endpoint}/${bucket}/${key}`);
  const host = url.host;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = crypto.createHash('sha256').update(bytes).digest('hex');
  const canonicalHeaders =
    `content-type:${mime}\nhost:${host}\nx-amz-content-sha256:${payloadHash}\nx-amz-date:${amzDate}\n`;
  const signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
  const canonicalRequest = `PUT\n/${bucket}/${key}\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${crypto
    .createHash('sha256')
    .update(canonicalRequest)
    .digest('hex')}`;
  const hmac = (k, d) => crypto.createHmac('sha256', k).update(d).digest();
  const signingKey = hmac(hmac(hmac(hmac(`AWS4${secretKey}`, dateStamp), region), 's3'), 'aws4_request');
  const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');

  const res = await fetch(url, {
    method: 'PUT',
    headers: {
      'Content-Type': mime,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${accessKey}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
    body: bytes,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`S3 上传失败 ${res.status} ${text.slice(0, 200)}`);
  }
  const base = (process.env.S3_PUBLIC_BASE || `${endpoint}/${bucket}`).replace(/\/+$/, '');
  return `${base}/${key}`;
}
