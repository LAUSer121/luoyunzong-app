// 资源存储驱动：local（服务器磁盘） / upyun（又拍云对象存储） / s3（缤纷云 S4 / R2 / MinIO 等）
//
// 客户端只认「资源 id」；存哪由这里决定：
//   - local：落盘 uploads/<id>，由本服务用 /assets/<id> 提供访问
//   - upyun：直传又拍云，返回 <UPYUN_DOMAIN>/<path>
//   - s3：SigV4 直传（缤纷云 S4 就是标准 S3），返回 <S3_PUBLIC_BASE>/<path>
//
// 配置来源（优先级从高到低）：
//   1) MySQL `app_settings` 里 skey='storage' 的 JSON —— 管理员在 App 里改的就是它；
//   2) server/.env —— 出厂默认（没在 App 里配过时用它）；
//   3) 内置默认 —— 存本地磁盘。
import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { pool, ORG_ID } from './db.mjs';

const UPLOAD_DIR = fileURLToPath(new URL('uploads/', import.meta.url));
const SETTINGS_KEY = 'storage';

/** .env 里的出厂默认值。 */
const envDefaults = () => ({
  driver: (process.env.STORAGE_DRIVER || 'local').toLowerCase(),
  endpoint: (process.env.S3_ENDPOINT || '').replace(/\/+$/, ''),
  region: process.env.S3_REGION || 'cn-east-1',
  bucket: process.env.S3_BUCKET || process.env.UPYUN_BUCKET || '',
  accessKey: process.env.S3_ACCESS_KEY_ID || '',
  secretKey: process.env.S3_SECRET_ACCESS_KEY || '',
  publicBase: (process.env.S3_PUBLIC_BASE || '').replace(/\/+$/, ''),
  upyunOperator: process.env.UPYUN_OPERATOR || '',
  upyunPassword: process.env.UPYUN_PASSWORD || '',
});

/** 当前生效的配置（内存缓存；保存后立刻刷新）。 */
let current = envDefaults();
/** 配置是不是来自数据库（界面用来提示「已保存到服务器」）。 */
let fromDatabase = false;

export const DRIVERS = ['local', 's3', 'upyun'];

/** 读数据库里的配置并刷新内存（启动时、以及每次保存后调用）。 */
export async function reloadStorageConfig() {
  try {
    const [rows] = await pool.query(
      'SELECT svalue FROM app_settings WHERE org_id = ? AND skey = ? LIMIT 1',
      [ORG_ID, SETTINGS_KEY],
    );
    const raw = rows.length ? rows[0].svalue : null;
    if (raw) {
      const saved = JSON.parse(String(raw));
      current = { ...envDefaults(), ...saved };
      fromDatabase = true;
      return current;
    }
  } catch (e) {
    console.error('[storage] 读取数据库配置失败，先用 .env：', e.message);
  }
  current = envDefaults();
  fromDatabase = false;
  return current;
}

/** 完整配置（含密钥）——只在服务端内部用，别直接回给客户端。 */
export const currentStorageConfig = () => ({ ...current, fromDatabase });

/** 给客户端看的版本：密钥只回「有没有设置」，绝不回明文。 */
export const publicStorageConfig = () => {
  const env = envDefaults();
  return {
    driver: current.driver,
    endpoint: current.endpoint,
    region: current.region,
    bucket: current.bucket,
    accessKey: current.accessKey,
    publicBase: current.publicBase,
    secretKeySet: Boolean(current.secretKey),
    secretKeyFromEnv: Boolean(!fromDatabase && env.secretKey),
    fromDatabase,
    // 又拍云那两个是可选的，一起回（密钥同样只回状态）
    upyunOperator: current.upyunOperator,
    upyunPasswordSet: Boolean(current.upyunPassword),
    drivers: DRIVERS,
  };
};

/** 保存配置：只覆盖传进来的字段；密钥传空字符串表示「保持原样」。 */
export async function saveStorageConfig(patch = {}) {
  const merged = { ...current };
  const text = (v) => (v == null ? undefined : String(v).trim());
  const setIf = (key, value) => {
    if (value !== undefined) merged[key] = value;
  };

  const driver = text(patch.driver);
  if (driver !== undefined) {
    if (!DRIVERS.includes(driver)) {
      throw new Error(`不支持的存储类型：${driver}（可选 ${DRIVERS.join(' / ')}）`);
    }
    merged.driver = driver;
  }
  setIf('endpoint', text(patch.endpoint)?.replace(/\/+$/, ''));
  setIf('region', text(patch.region));
  setIf('bucket', text(patch.bucket));
  setIf('accessKey', text(patch.accessKey));
  setIf('publicBase', text(patch.publicBase)?.replace(/\/+$/, ''));
  setIf('upyunOperator', text(patch.upyunOperator));

  // 密钥：留空 = 不改（界面上也看不到明文，避免误清空）
  const secret = text(patch.secretKey);
  if (secret !== undefined && secret !== '') merged.secretKey = secret;
  const upyunPwd = text(patch.upyunPassword);
  if (upyunPwd !== undefined && upyunPwd !== '') merged.upyunPassword = upyunPwd;

  if (merged.driver === 's3') {
    const missing = ['endpoint', 'bucket', 'accessKey', 'secretKey'].filter(
      (k) => !merged[k],
    );
    if (missing.length) {
      throw new Error(`S3/缤纷云配置不完整，缺少：${missing.join(' / ')}`);
    }
  }
  if (merged.driver === 'upyun') {
    const missing = ['bucket', 'upyunOperator', 'upyunPassword'].filter(
      (k) => !merged[k],
    );
    if (missing.length) {
      throw new Error(`又拍云配置不完整，缺少：${missing.join(' / ')}`);
    }
  }

  await pool.query(
    `INSERT INTO app_settings (org_id, skey, svalue) VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE svalue = VALUES(svalue)`,
    [ORG_ID, SETTINGS_KEY, JSON.stringify(merged)],
  );
  await reloadStorageConfig();
  return publicStorageConfig();
}

export const storageInfo = () => ({
  driver: current.driver,
  bucket: current.bucket,
  domain: current.publicBase,
  fromDatabase,
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
  if (current.driver === 'upyun') {
    const url = await putUpyun({ id, mime, bytes });
    return { url, driver: 'upyun' };
  }
  if (current.driver === 's3') {
    const url = await putS3({ id, mime, bytes });
    return { url, driver: 's3' };
  }
  await fs.mkdir(UPLOAD_DIR, { recursive: true });
  await fs.writeFile(path.join(UPLOAD_DIR, `${id}.${extOf(mime)}`), bytes);
  return { url: '', driver: 'local' };
}

/** 取资源字节：本地读盘；对象存储则按 URL / 签名回源。 */
export async function getAsset({ id, mime, url }) {
  if (!url) {
    // 没配公开域名时（私有桶）：S3 用签名请求按 key 取回，由本服务中转给客户端。
    if (current.driver === 's3') {
      return getS3SignedByKey(current.bucket, keyOf(id, mime));
    }
    const file = path.join(UPLOAD_DIR, `${id}.${extOf(mime)}`);
    try {
      return await fs.readFile(file);
    } catch {
      return null;
    }
  }
  try {
    const res = await fetch(url);
    if (res.ok) return Buffer.from(await res.arrayBuffer());
  } catch {
    // 落到下面的签名回源
  }
  if (current.driver === 's3') {
    const target = new URL(url);
    const parts = target.pathname.replace(/^\/+/, '').split('/');
    const bucket = parts.shift() || current.bucket;
    return getS3SignedByKey(bucket, parts.join('/'));
  }
  return null;
}

/**
 * 上传/回读/删除一个探针对象，用来在 App 里「测试连接」。
 * 返回 { ok, message }，失败时把对象存储的原话带回去（例如权限不足的 AccessDenied）。
 */
export async function testStorage() {
  const id = `probe-${Date.now()}`;
  const mime = 'text/plain';
  const bytes = Buffer.from('luoyunzong storage probe', 'utf8');
  const driver = current.driver;
  try {
    const { url } = await putAsset({ id, mime, bytes });
    if (driver === 'local') {
      const back = await getAsset({ id, mime, url: '' });
      await fs.rm(path.join(UPLOAD_DIR, `${id}.${extOf(mime)}`), { force: true });
      return {
        ok: Boolean(back),
        message: back ? `本地磁盘写入正常（${bytes.length} 字节）` : '本地磁盘写入后读不回来',
      };
    }
    const back = url
      ? await getAsset({ id, mime, url })
      : current.driver === 's3'
      ? await getS3SignedByKey(current.bucket, keyOf(id, mime))
      : await getAsset({ id, mime, url: '' });
    if (driver === 's3') await deleteS3(id, mime);
    if (driver === 'upyun') await deleteUpyun(id, mime);
    return {
      ok: Boolean(back),
      message: back
        ? `${driver} 上传并回读成功${url ? '：' + url : ''}`
        : `${driver} 上传成功但回读失败（私有桶请填公开域名，或保持留空让服务端中转）`,
    };
  } catch (e) {
    return { ok: false, message: e.message };
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
  const bucket = current.bucket;
  const operator = current.upyunOperator;
  const password = current.upyunPassword;
  if (!bucket || !operator || !password) {
    throw new Error('又拍云配置不完整：需要 桶名 / 操作员 / 操作员密码');
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
  return current.publicBase ? `${current.publicBase}/${keyOf(id, mime)}` : '';
}

async function deleteUpyun({ id, mime }) {
  const bucket = current.bucket;
  const operator = current.upyunOperator;
  const password = current.upyunPassword;
  if (!bucket || !operator || !password) return;
  const uriPath = `/${bucket}/${keyOf(id, mime)}`;
  const date = new Date().toUTCString();
  const md5Password = crypto.createHash('md5').update(password).digest('hex');
  const signature = crypto
    .createHash('md5')
    .update(`DELETE&${uriPath}&${date}&0&${md5Password}`)
    .digest('hex');
  await fetch(`https://v0.api.upyun.com${uriPath}`, {
    method: 'DELETE',
    headers: {
      Authorization: `UPYUN ${operator}:${signature}`,
      Date: date,
    },
  }).catch(() => {});
}

// ---------------------------------------------------------------------------
// S3 / 缤纷云 S4 / Cloudflare R2 / MinIO：手写 SigV4（避免引入 aws-sdk）
//   缤纷云：endpoint https://s3.bitiful.net，region cn-east-1，走的是标准 S3。
// ---------------------------------------------------------------------------
const s3Sign = ({ method, bucket, key, payloadHash, contentType }) => {
  const endpoint = (current.endpoint || '').replace(/\/+$/, '');
  const region = current.region || 'cn-east-1';
  const accessKey = current.accessKey;
  const secretKey = current.secretKey;
  if (!endpoint || !bucket || !accessKey || !secretKey) {
    throw new Error('对象存储配置不完整：需要 Endpoint / 桶名 / AccessKey / SecretKey');
  }
  const url = new URL(`${endpoint}/${bucket}/${key}`);
  const host = url.host;
  const amzDate = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const headers = {
    host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': amzDate,
  };
  if (contentType) headers['content-type'] = contentType;
  const sortedKeys = Object.keys(headers).sort();
  const canonicalHeaders = sortedKeys.map((k) => `${k}:${headers[k]}\n`).join('');
  const signedHeaders = sortedKeys.join(';');
  const canonicalRequest = `${method}\n/${bucket}/${key}\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
  const scope = `${dateStamp}/${region}/s3/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${scope}\n${crypto
    .createHash('sha256')
    .update(canonicalRequest)
    .digest('hex')}`;
  const hmac = (k, d) => crypto.createHmac('sha256', k).update(d).digest();
  const signingKey = hmac(
    hmac(hmac(hmac(`AWS4${secretKey}`, dateStamp), region), 's3'),
    'aws4_request',
  );
  const signature = crypto
    .createHmac('sha256', signingKey)
    .update(stringToSign)
    .digest('hex');
  return {
    url: url.toString(),
    headers: {
      ...headers,
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${accessKey}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
  };
};

async function putS3({ id, mime, bytes }) {
  const key = keyOf(id, mime);
  const payloadHash = crypto.createHash('sha256').update(bytes).digest('hex');
  const { url, headers } = s3Sign({
    method: 'PUT',
    bucket: current.bucket,
    key,
    payloadHash,
    contentType: mime,
  });
  const res = await fetch(url, { method: 'PUT', headers, body: bytes });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(
      `对象存储上传失败 ${res.status} ${s3Hint(res.status)} ${text.slice(0, 200)}`,
    );
  }
  const base = (current.publicBase || '').replace(/\/+$/, '');
  return base ? `${base}/${key}` : '';
}

/** 私有桶回源：用签名 GET 把字节拉回来（密钥不下发给客户端）。 */
async function getS3SignedByKey(bucket, key) {
  try {
    const emptyHash = crypto
      .createHash('sha256')
      .update(Buffer.alloc(0))
      .digest('hex');
    const { url, headers } = s3Sign({
      method: 'GET',
      bucket,
      key,
      payloadHash: emptyHash,
    });
    const res = await fetch(url, { headers });
    if (!res.ok) return null;
    return Buffer.from(await res.arrayBuffer());
  } catch {
    return null;
  }
}

async function deleteS3({ id, mime }) {
  try {
    const emptyHash = crypto
      .createHash('sha256')
      .update(Buffer.alloc(0))
      .digest('hex');
    const { url, headers } = s3Sign({
      method: 'DELETE',
      bucket: current.bucket,
      key: keyOf(id, mime),
      payloadHash: emptyHash,
    });
    await fetch(url, { method: 'DELETE', headers });
  } catch {
    // 清理失败不影响主流程
  }
}

/** 把常见的对象存储报错翻译成好懂的提示。 */
function s3Hint(status) {
  if (status === 403) {
    return '（凭据没权限：去缤纷云控制台「子账户&Key」给这个子用户分配该桶的读写权限）';
  }
  if (status === 404) return '（桶名或 Endpoint 不对）';
  if (status === 400) return '（区域 region 或签名不匹配）';
  return '';
}
