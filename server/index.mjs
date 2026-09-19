// 落云宗 · 云同步服务端
//   Aiven MySQL 存存档与资源索引；资源可落本地磁盘或直传又拍云 / S3。
//
// 启动：node index.mjs       （配置见 .env，模板见 .env.example）
import 'dotenv/config';
import crypto from 'node:crypto';
import express from 'express';
import { pool, ORG_ID } from './db.mjs';
import { putAsset, getAsset, storageInfo } from './storage.mjs';
import {
  publicStorageConfig,
  saveStorageConfig,
  reloadStorageConfig,
  testStorage,
  maxBytesForMime,
  reloadLimits,
  currentLimits,
  removeLocalAsset,
  presignS3,
  publicUrlFor,
} from './storage.mjs';

const app = express();
const PORT = Number(process.env.PORT || 8080);
const TOKEN = process.env.API_TOKEN || '';

app.disable('x-powered-by');
// 存档可能几 MB；资源走单独的二进制接口
app.use(express.json({ limit: '32mb' }));

// ---- CORS：浏览器版（单文件 HTML）需要 ----
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization,Content-Type,X-Requested-With',
  );
  res.setHeader('Access-Control-Max-Age', '86400');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// ---- 访问日志（便于确认客户端是否连上；不含敏感信息）----
app.use((req, res, next) => {
  const started = Date.now();
  res.on('finish', () => {
    console.log(
      `[api] ${req.method} ${req.path} ${res.statusCode} ${Date.now() - started}ms` +
        (req.headers['user-agent']
          ? ` ua=${String(req.headers['user-agent']).slice(0, 32)}`
          : ''),
    );
  });
  next();
});

// ---- 鉴权 ----
function auth(req, res, next) {
  if (!TOKEN) return next(); // 未配置令牌则不校验（仅本机/内网调试）
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (token !== TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
}

const MIME_EXT = {'image/jpeg':'jpg','image/png':'png','image/webp':'webp','image/gif':'gif','video/mp4':'mp4','video/webm':'webm','video/quicktime':'mov'};
const extOfMime = (mime) => MIME_EXT[mime] || 'bin';

const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---------------------------------------------------------------------------
// 健康检查
// ---------------------------------------------------------------------------
app.get(
  '/api/health',
  asyncRoute(async (_req, res) => {
    const [rows] = await pool.query('SELECT NOW() AS now, VERSION() AS version');
    // 健康检查是公开接口：只回存储类型，不回桶名/域名等细节
    res.json({
      ok: true,
      db: { ok: true, version: rows[0].version, now: rows[0].now },
      storage: { driver: storageInfo().driver },
      limits: currentLimits(),
      org: ORG_ID,
    });
  }),
);

// ---------------------------------------------------------------------------
// 对象存储配置（缤纷云 / 又拍云 / S3）
//   管理员在 App 里改 → 存到 MySQL 的 app_settings → 之后上传的资源直接进对象存储。
//   密钥只在服务端保存，GET 只回「有没有设置」，不回明文。
// ---------------------------------------------------------------------------
app.get(
  '/api/storage',
  auth,
  asyncRoute(async (_req, res) => {
    res.json(publicStorageConfig());
  }),
);

app.put(
  '/api/storage',
  auth,
  asyncRoute(async (req, res) => {
    try {
      const saved = await saveStorageConfig(req.body || {});
      res.json({ ok: true, config: saved });
    } catch (e) {
      res.status(400).json({ error: e.message });
    }
  }),
);

app.post(
  '/api/storage/test',
  auth,
  asyncRoute(async (_req, res) => {
    const result = await testStorage();
    res.json(result);
  }),
);

// ---------------------------------------------------------------------------
// 管理员密码校验（优先用 admins 表，未配置时回落到存档里的明文密码）
// ---------------------------------------------------------------------------
app.post(
  '/api/auth/verify',
  asyncRoute(async (req, res) => {
    const password = String(req.body?.password ?? '');
    const [admins] = await pool.query(
      'SELECT password_hash FROM admins WHERE org_id = ? ORDER BY id LIMIT 1',
      [ORG_ID],
    );
    if (admins.length && admins[0].password_hash) {
      const hash = admins[0].password_hash;
      // 支持 bcrypt($2...) 与 sha256 十六进制两种
      let ok = false;
      if (hash.startsWith('$2')) {
        const bcrypt = await import('bcryptjs').catch(() => null);
        ok = bcrypt ? await bcrypt.compare(password, hash) : false;
      } else {
        ok = crypto.createHash('sha256').update(password).digest('hex') === hash;
      }
      return res.json({ ok });
    }
    const [archives] = await pool.query('SELECT payload FROM archives WHERE org_id = ?', [ORG_ID]);
    const fallback = process.env.ADMIN_PASSWORD || '123456';
    let archivePassword = fallback;
    if (archives.length) {
      try {
        archivePassword = JSON.parse(archives[0].payload).adminPassword || fallback;
      } catch {}
    }
    res.json({ ok: password === archivePassword });
  }),
);

// ---------------------------------------------------------------------------
// 整包存档
// ---------------------------------------------------------------------------
app.get(
  '/api/archive',
  auth,
  asyncRoute(async (_req, res) => {
    const [rows] = await pool.query(
      'SELECT payload, revision, updated_at FROM archives WHERE org_id = ? LIMIT 1',
      [ORG_ID],
    );
    if (!rows.length) return res.status(404).json({ error: 'not found' });
    // 同步用元信息：客户端据此判断「谁更新」，决定是拉取还是推送
    res.setHeader('X-Revision', String(rows[0].revision));
    res.setHeader('X-Updated-At', new Date(rows[0].updated_at).toISOString());
    res.type('application/json').send(rows[0].payload);
  }),
);

app.put(
  '/api/archive',
  auth,
  asyncRoute(async (req, res) => {
    if (!req.body || typeof req.body !== 'object') {
      return res.status(400).json({ error: 'body must be a JSON object' });
    }
    const payload = JSON.stringify(req.body);
    await pool.query(
      `INSERT INTO archives (org_id, payload, archive_version)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE payload = VALUES(payload), revision = revision + 1`,
      [ORG_ID, payload, Number(req.body.archiveVersion || 4)],
    );
    const [rows] = await pool.query(
      'SELECT revision, updated_at FROM archives WHERE org_id = ?',
      [ORG_ID],
    );
    res.json({ ok: true, revision: rows[0].revision, updatedAt: rows[0].updated_at });
  }),
);

app.delete(
  '/api/archive',
  auth,
  asyncRoute(async (_req, res) => {
    await pool.query('DELETE FROM archives WHERE org_id = ?', [ORG_ID]);
    res.json({ ok: true });
  }),
);

// 清空云端资源（管理员在 App 里「重置云端」时可选）
// 说明：只删数据库索引；对象存储里的对象会变成孤儿（可在缤纷云控制台按前缀
//       luoyunzong/ 批量清理），本地驱动则顺手删掉磁盘文件。
app.delete(
  '/api/assets',
  auth,
  asyncRoute(async (_req, res) => {
    const [before] = await pool.query(
      'SELECT id, mime, driver FROM assets WHERE org_id = ?',
      [ORG_ID],
    );
    await pool.query('DELETE FROM assets WHERE org_id = ?', [ORG_ID]);
    let removedFiles = 0;
    for (const row of before) {
      if (row.driver === 'local') {
        try {
          await removeLocalAsset({ id: row.id, mime: row.mime });
          removedFiles++;
        } catch {
          // 文件不存在也不影响
        }
      }
    }
    res.json({ ok: true, deleted: before.length, removedFiles });
  }),
);

// ---------------------------------------------------------------------------
// 资源：头像 / 立绘 / 背景图 / 动态视频
//   POST /api/assets?id=<内容哈希>&mime=<mime>   body = 二进制
//   GET  /api/assets/batch?ids=a,b,c             → { id: base64 }
//   GET  /assets/<id>?mime=                      → 本地驱动直接回源
// ---------------------------------------------------------------------------
// 音频/视频可能很大：express.raw 这里给一个进程级硬上限（MAX_UPLOAD_MB，默认 512MB），
// 真正的上限（管理员在 App 里配的）在下面按 mime 判断。
app.post(
  '/api/assets',
  auth,
  express.raw({
    type: '*/*',
    limit: `${Number(process.env.MAX_UPLOAD_MB || 512)}mb`,
  }),
  asyncRoute(async (req, res) => {
    const id = String(req.query.id || '').trim();
    const mime = String(req.query.mime || req.headers['content-type'] || 'application/octet-stream');
    const bytes = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
    if (!id) return res.status(400).json({ error: 'id is required' });
    if (!bytes.length) return res.status(400).json({ error: 'empty body' });

    // 管理员在 App 里配的上限（视频/图片分别一份）
    const limit = maxBytesForMime(mime);
    if (bytes.length > limit) {
      const mb = (limit / 1024 / 1024).toFixed(0);
      return res.status(413).json({
        error:
          `文件 ${(bytes.length / 1024 / 1024).toFixed(1)}MB 超过当前上限 ${mb}MB；` +
          `管理员可在「设置 → 云端资源存储 → 上传上限」里调大`,
        limitMB: Number(mb),
      });
    }

    const [existing] = await pool.query(
      'SELECT id FROM assets WHERE org_id = ? AND id = ?',
      [ORG_ID, id],
    );
    if (existing.length) return res.json({ id, deduplicated: true });

    const { url, driver } = await putAsset({ id, mime, bytes });
    // 字节已经落到对象存储/磁盘了，数据库只留索引（Aiven 免费版只有 1GB，
    // 视频绝不能再往库里塞一份）。
    await pool.query(
      `INSERT INTO assets (org_id, id, mime, byte_size, bytes, url, driver)
       VALUES (?, ?, ?, ?, NULL, ?, ?)
       ON DUPLICATE KEY UPDATE url = VALUES(url), driver = VALUES(driver), byte_size = VALUES(byte_size)`,
      [ORG_ID, id, mime, bytes.length, url || null, driver],
    );
    res.json({ id, url, driver, size: bytes.length });
  }),
);

app.get(
  '/api/assets/batch',
  auth,
  asyncRoute(async (req, res) => {
    const ids = String(req.query.ids || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 300);
    if (!ids.length) return res.json({});
    const [rows] = await pool.query(
      `SELECT id, mime, url, bytes FROM assets
        WHERE org_id = ? AND id IN (${ids.map(() => '?').join(',')})`,
      [ORG_ID, ...ids],
    );
    const out = {};
    for (const row of rows) {
      let bytes = row.bytes ? Buffer.from(row.bytes) : null;
      if (!bytes) bytes = await getAsset({ id: row.id, mime: row.mime, url: row.url });
      if (bytes) out[row.id] = bytes.toString('base64');
    }
    res.json(out);
  }),
);

// ---------------------------------------------------------------------------
// 直传（预签名）：服务端只签名，字节由客户端直接进对象存储。
// Vercel/Serverless 上有 4.5MB 请求体上限，大视频必须走这条。
//   POST /api/assets/sign    ?id=&mime=&size=  → { uploadUrl, headers, driver }
//   POST /api/assets/commit  ?id=&mime=&size=  → 登记到数据库（去重）
//   GET  /api/assets/links   ?ids=a,b,c        → { id: 可直接下载的 url }
// ---------------------------------------------------------------------------
app.post(
  '/api/assets/sign',
  auth,
  asyncRoute(async (req, res) => {
    const id = String(req.query.id || '').trim();
    const mime = String(req.query.mime || 'application/octet-stream');
    const size = Number(req.query.size || 0);
    if (!id) return res.status(400).json({ error: 'id is required' });
    const limit = maxBytesForMime(mime);
    if (size > limit) {
      const mb = (limit / 1024 / 1024).toFixed(0);
      return res.status(413).json({
        error:
          `文件 ${(size / 1024 / 1024).toFixed(1)}MB 超过当前上限 ${mb}MB；` +
          `管理员可在「设置 → 云端资源存储 → 上传上限」里调大`,
      });
    }
    if (storageInfo().driver !== 's3') {
      // 非对象存储：直接告诉客户端走老接口（本地磁盘/又拍云没有预签名）
      return res.json({ direct: false, driver: storageInfo().driver });
    }
    const uploadUrl = presignS3({ id, mime, method: 'PUT', expires: 3600 });
    // 私有桶 + 没配公开域名时，回读由 links 接口给预签名 GET
    const url = publicUrlFor(id, mime);
    return res.json({
      direct: true,
      driver: 's3',
      uploadUrl,
      url,
      // 必须原样带上这两个头，签名才对得上
      headers: { 'Content-Type': mime, 'x-amz-content-sha256': 'UNSIGNED-PAYLOAD' },
      expiresIn: 3600,
    });
  }),
);

app.post(
  '/api/assets/commit',
  auth,
  asyncRoute(async (req, res) => {
    const id = String(req.query.id || '').trim();
    const mime = String(req.query.mime || 'application/octet-stream');
    const size = Number(req.query.size || 0);
    if (!id) return res.status(400).json({ error: 'id is required' });
    const driver = storageInfo().driver;
    const url = publicUrlFor(id, mime);
    await pool.query(
      `INSERT INTO assets (org_id, id, mime, byte_size, bytes, url, driver)
       VALUES (?, ?, ?, ?, NULL, ?, ?)
       ON DUPLICATE KEY UPDATE byte_size = VALUES(byte_size), url = VALUES(url), driver = VALUES(driver)`,
      [ORG_ID, id, mime, size, url || null, driver],
    );
    res.json({ ok: true, id, url, driver });
  }),
);

app.get(
  '/api/assets/links',
  auth,
  asyncRoute(async (req, res) => {
    const ids = String(req.query.ids || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 300);
    if (!ids.length) return res.json({});
    const [rows] = await pool.query(
      `SELECT id, mime, url FROM assets
        WHERE org_id = ? AND id IN (${ids.map(() => '?').join(',')})`,
      [ORG_ID, ...ids],
    );
    const driver = storageInfo().driver;
    const out = {};
    for (const row of rows) {
      if (row.url) {
        out[row.id] = row.url;
      } else if (driver === 's3') {
        // 私有桶：给一个有效期 2 小时的预签名 GET
        out[row.id] = presignS3({
          id: row.id,
          mime: row.mime,
          method: 'GET',
          expires: 7200,
        });
      } else {
        // 本地磁盘：由本服务 /assets/<id>.<ext> 提供
        out[row.id] = `/assets/${row.id}.${extOfMime(row.mime)}`;
      }
    }
    res.json(out);
  }),
);

// 本地驱动：直接把文件回源（对象存储则客户端直接用 url，不走这里）
app.get(
  '/assets/:name',
  asyncRoute(async (req, res) => {
    const name = String(req.params.name);
    const dot = name.lastIndexOf('.');
    const id = dot > 0 ? name.slice(0, dot) : name;
    const [rows] = await pool.query(
      'SELECT mime, url FROM assets WHERE org_id = ? AND id = ? LIMIT 1',
      [ORG_ID, id],
    );
    if (!rows.length) return res.sendStatus(404);
    if (rows[0].url) return res.redirect(rows[0].url);
    const bytes = await getAsset({ id, mime: rows[0].mime, url: '' });
    if (!bytes) return res.sendStatus(404);
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.type(rows[0].mime).send(bytes);
  }),
);

// ---------------------------------------------------------------------------
app.use((err, _req, res, _next) => {
  console.error('[api] error:', err.message);
  res.status(500).json({ error: err.message });
});

/** 启动前把数据库里的配置读进来（存储驱动 / 上传上限）。 */
export async function warmup() {
  await reloadStorageConfig().catch((e) =>
    console.error('[api] 读取存储配置失败:', e.message),
  );
  await reloadLimits().catch((e) =>
    console.error('[api] 读取上传上限失败:', e.message),
  );
}

export { app };
export default app;

// 直接 `node index.mjs` 跑时才监听端口；Vercel 之类由平台把 app 当 handler 用。
const isServerless = Boolean(process.env.VERCEL || process.env.AWS_LAMBDA_FUNCTION_NAME);
if (!isServerless) {
  warmup().catch(() => {});
  app.listen(PORT, () => {
    const s = storageInfo();
    console.log(`[api] 落云宗服务端已启动: http://127.0.0.1:${PORT}`);
    console.log(
      `[api] 归档库: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME} org=${ORG_ID}`,
    );
    console.log(
      `[api] 资源存储: ${s.driver}${s.bucket ? ` (${s.bucket})` : ''}` +
        `${s.fromDatabase ? ' [数据库里配置的]' : ' [来自 .env]'}`,
    );
  });
}
