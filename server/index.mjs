// 落云宗 · 云同步服务端
//   Aiven MySQL 存存档与资源索引；资源可落本地磁盘或直传又拍云 / S3。
//
// 启动：node index.mjs       （配置见 .env，模板见 .env.example）
import 'dotenv/config';
import crypto from 'node:crypto';
import express from 'express';
import { pool, ORG_ID } from './db.mjs';
import { putAsset, getAsset, storageInfo } from './storage.mjs';

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

// ---- 鉴权 ----
function auth(req, res, next) {
  if (!TOKEN) return next(); // 未配置令牌则不校验（仅本机/内网调试）
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (token !== TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
}

const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---------------------------------------------------------------------------
// 健康检查
// ---------------------------------------------------------------------------
app.get(
  '/api/health',
  asyncRoute(async (_req, res) => {
    const [rows] = await pool.query('SELECT NOW() AS now, VERSION() AS version');
    res.json({
      ok: true,
      db: { ok: true, version: rows[0].version, now: rows[0].now },
      storage: storageInfo(),
      org: ORG_ID,
    });
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
    res.setHeader('X-Revision', String(rows[0].revision));
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

// ---------------------------------------------------------------------------
// 资源：头像 / 立绘 / 背景图 / 动态视频
//   POST /api/assets?id=<内容哈希>&mime=<mime>   body = 二进制
//   GET  /api/assets/batch?ids=a,b,c             → { id: base64 }
//   GET  /assets/<id>?mime=                      → 本地驱动直接回源
// ---------------------------------------------------------------------------
app.post(
  '/api/assets',
  auth,
  express.raw({ type: '*/*', limit: '32mb' }),
  asyncRoute(async (req, res) => {
    const id = String(req.query.id || '').trim();
    const mime = String(req.query.mime || req.headers['content-type'] || 'application/octet-stream');
    const bytes = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
    if (!id) return res.status(400).json({ error: 'id is required' });
    if (!bytes.length) return res.status(400).json({ error: 'empty body' });
    if (bytes.length > 16 * 1024 * 1024) {
      return res.status(413).json({ error: 'too large for database storage, use object storage' });
    }

    const [existing] = await pool.query(
      'SELECT id FROM assets WHERE org_id = ? AND id = ?',
      [ORG_ID, id],
    );
    if (existing.length) return res.json({ id, deduplicated: true });

    const { url, driver } = await putAsset({ id, mime, bytes });
    await pool.query(
      `INSERT INTO assets (org_id, id, mime, byte_size, bytes, url, driver)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE url = VALUES(url), driver = VALUES(driver)`,
      [ORG_ID, id, mime, bytes.length, driver === 'local' ? null : bytes, url || null, driver],
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

app.listen(PORT, () => {
  const s = storageInfo();
  console.log(`[api] 落云宗服务端已启动: http://127.0.0.1:${PORT}`);
  console.log(`[api] 归档库: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME} org=${ORG_ID}`);
  console.log(`[api] 资源存储: ${s.driver}${s.bucket ? ` (${s.bucket})` : ''}`);
});
