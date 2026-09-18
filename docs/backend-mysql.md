# 后期接入 MySQL：接口约定与表结构

客户端已经把数据访问抽象成 `LuoyunRepository`（`lib/domain/repository.dart`）。
现在默认使用 `LocalRepository`（本地文件 / 浏览器存储）；只要服务端按本文约定实现，
把 `lib/main.dart` 里的仓储实现换成 `ApiRepository` 即可切到 MySQL，界面代码无需改动。

```dart
// lib/main.dart —— 切换数据源
final ApiClient client = ApiClient(baseUrl: 'https://your.server', token: 'TOKEN');
final LuoyunRepository repo = ApiRepository(
  client: client,
  fallback: LocalRepository(), // 断网时自动回落本地，不丢数据
);
final AppState state = AppState(repository: repo);
```

---

## 1. REST 接口

所有请求/响应均为 `application/json; charset=utf-8`；鉴权用 `Authorization: Bearer <token>`。

| 方法 | 路径 | 说明 | 请求体 | 响应 |
| --- | --- | --- | --- | --- |
| GET | `/api/health` | 健康检查（设置页「测试连接」调用） | — | `{"ok":true}` |
| POST | `/api/auth/verify` | 校验管理员密码 | `{"password":"..."}` | `{"ok":true}` / `{"ok":false}` |
| GET | `/api/archive` | 读取整包存档 | — | 存档 JSON（与 `Archive.toJson()` 同构） |
| PUT | `/api/archive` | 覆盖写入整包存档 | 存档 JSON | `{"ok":true,"updatedAt":"..."}` |
| DELETE | `/api/archive` | 清空存档 | — | `{"ok":true}` |

**为什么整包读写**：旧版是单文件存档语义（导出/导入一份 JSON），整包读写让迁移零成本，
也避免前后端字段级别的双份模型维护。数据量在「几十名成员 + 若干场考试 + base64 立绘」量级，
单包通常在几百 KB 到几 MB，`MEDIUMTEXT` 足够；如果立绘/视频体积增大，见 §3 的演进建议。

## 2. MySQL 表结构

```sql
-- schema.sql
CREATE DATABASE IF NOT EXISTS luoyunzong
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE luoyunzong;

-- 整包存档：一行一个宗门（多宗门/多服务器时用 org_id 区分）
CREATE TABLE IF NOT EXISTS archives (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id        VARCHAR(64)  NOT NULL DEFAULT 'default' COMMENT '宗门标识',
  archive_version INT         NOT NULL DEFAULT 4,
  payload       LONGTEXT     NOT NULL COMMENT 'Archive.toJson() 的完整 JSON',
  revision      BIGINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '乐观锁版本号',
  updated_by    VARCHAR(64)  NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_org (org_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 管理员账号（替代存档里的明文 adminPassword）
CREATE TABLE IF NOT EXISTS admins (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id        VARCHAR(64)  NOT NULL DEFAULT 'default',
  username      VARCHAR(64)  NOT NULL,
  password_hash VARCHAR(255) NOT NULL COMMENT 'bcrypt / argon2 哈希',
  role          ENUM('owner','admin','viewer') NOT NULL DEFAULT 'admin',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_org_user (org_id, username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 操作审计（可选，便于回溯谁改了名单/成绩）
CREATE TABLE IF NOT EXISTS audit_logs (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id     VARCHAR(64)  NOT NULL DEFAULT 'default',
  actor      VARCHAR(64)  NULL,
  action     VARCHAR(64)  NOT NULL,
  detail     TEXT         NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_org_time (org_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 规范化拆分（可选，第二阶段）

如果后续需要按人查询、跨端并发编辑，把整包拆成关系表（`members` / `tower_records` /
`peaks` / `peak_members` / `exam_sessions` / `exam_records` / `task_configs`），
由服务端维护，客户端接口保持不变（仍读写 `/api/archive`，服务端内部做拆分与合并）：

```sql
CREATE TABLE members (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  org_id VARCHAR(64) NOT NULL DEFAULT 'default',
  name VARCHAR(64) NOT NULL,
  role VARCHAR(32) NOT NULL,
  main_rank VARCHAR(16) NOT NULL DEFAULT '炼气',
  sub_rank  VARCHAR(16) NOT NULL DEFAULT '前期',
  contribution INT NOT NULL DEFAULT 0,
  sub_roles JSON NULL,
  avatar   MEDIUMTEXT NULL,
  portrait MEDIUMTEXT NULL,
  video    MEDIUMTEXT NULL,
  UNIQUE KEY uk_org_name (org_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_sessions (
  id CHAR(24) PRIMARY KEY,
  org_id VARCHAR(64) NOT NULL DEFAULT 'default',
  name VARCHAR(128) NOT NULL,
  time VARCHAR(32) NOT NULL DEFAULT '',
  UNIQUE KEY uk_org_exam (org_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exam_records (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_id CHAR(24) NOT NULL,
  member_name VARCHAR(64) NOT NULL,
  score DECIMAL(8,2) NOT NULL,
  UNIQUE KEY uk_session_member (session_id, member_name),
  CONSTRAINT fk_exam_session FOREIGN KEY (session_id) REFERENCES exam_sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## 3. 大文件（立绘 / 视频）演进建议

存档中的 `avatar` / `portrait` / `video` 目前是 base64 data URL。接后端后建议改为对象存储：

1. 客户端上传接口 `POST /api/assets`（multipart）→ 返回 `{"url":"https://.../a.jpg"}`；
2. 存档里只保存 URL，服务端可继续把 URL 存进 `members.portrait`；
3. `MediaUrl.resolve()` 兼容两类值：`data:` 前缀直接解码，`http(s):` 直接交给图片组件加载。

客户端 `lib/core/image_utils.dart` 已提供 `dataUrlToBytes`，改造时可直接复用。

## 4. 服务端参考实现（Node + Express + mysql2）

```js
// server/index.js  —  最小可用实现，配合上面的 schema.sql
import express from 'express';
import mysql from 'mysql2/promise';
import bcrypt from 'bcryptjs';

const pool = mysql.createPool({
  host: process.env.DB_HOST ?? '127.0.0.1',
  user: process.env.DB_USER ?? 'root',
  password: process.env.DB_PASSWORD ?? '',
  database: process.env.DB_NAME ?? 'luoyunzong',
  waitForConnections: true,
  connectionLimit: 10,
});

const app = express();
app.use(express.json({ limit: '32mb' }));

const ORG = process.env.ORG_ID ?? 'default';
const TOKEN = process.env.API_TOKEN ?? 'dev-token';

function auth(req, res, next) {
  if (req.headers.authorization !== `Bearer ${TOKEN}`) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  next();
}

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.post('/api/auth/verify', async (req, res) => {
  const [rows] = await pool.query(
    'SELECT password_hash FROM admins WHERE org_id = ? ORDER BY id LIMIT 1', [ORG],
  );
  const hash = rows[0]?.password_hash;
  const fallback = process.env.ADMIN_PASSWORD ?? '123456';
  const ok = hash ? await bcrypt.compare(req.body.password ?? '', hash)
                  : (req.body.password ?? '') === fallback;
  res.json({ ok });
});

app.get('/api/archive', auth, async (_req, res) => {
  const [rows] = await pool.query(
    'SELECT payload FROM archives WHERE org_id = ? LIMIT 1', [ORG],
  );
  if (!rows.length) return res.status(404).json({ error: 'not found' });
  res.type('application/json').send(rows[0].payload);
});

app.put('/api/archive', auth, async (req, res) => {
  const payload = JSON.stringify(req.body);
  await pool.query(
    `INSERT INTO archives (org_id, payload) VALUES (?, ?)
     ON DUPLICATE KEY UPDATE payload = VALUES(payload), revision = revision + 1`,
    [ORG, payload],
  );
  res.json({ ok: true, updatedAt: new Date().toISOString() });
});

app.delete('/api/archive', auth, async (_req, res) => {
  await pool.query('DELETE FROM archives WHERE org_id = ?', [ORG]);
  res.json({ ok: true });
});

app.listen(process.env.PORT ?? 8080, () => console.log('luoyunzong api ready'));
```

## 5. 切换与回滚

1. 设置页「数据源」填写服务端地址与令牌 → 点「保存并测试连接」确认 `GET /api/health` 通过。
2. 首次切换前先「导出 JSON 存档」备份（本地存档不受影响）。
3. `ApiRepository` 带 `fallback`：网络异常时读写自动回落本地，并在设置页显示「离线兜底」。
4. 回滚：把 `main.dart` 的仓储换回 `LocalRepository` 即可，数据格式完全一致。

---

## 6. 头像 / 立绘 / 背景图 / 视频放哪（已实现客户端侧）

先说体积，决定放哪：

| 内容 | 现在的大小（程序里就是这么多） |
| --- | --- |
| 头像（256px JPEG q85） | 约 20–60 KB |
| 立绘（720px JPEG q90） | 约 150–400 KB |
| 背景图（1920px JPEG q85） | 约 300–900 KB |
| 动态视频 | 单条上限 20 MB（`kVideoMaxBytes`） |

按 30 人 + 每人 1 张立绘 + 10 条短视频估算：**图片 ≈ 12 MB，视频 ≈ 200 MB**。
结论：**图片完全可以放 MySQL；视频建议放对象存储**。

### 方案 A：整包塞 MySQL（最省事）

`archives.payload LONGTEXT` 里就是完整 JSON，图片/视频的 base64 一起进去。
适合：几个人用、视频少。要注意：

```ini
# my.cnf
max_allowed_packet = 64M      # MySQL 8 默认 64M，5.7 只有 4M，不改会插入失败
innodb_log_file_size = 256M
```

### 方案 B：图片进 assets 表，存档只留引用（客户端已实现，推荐）

客户端在「远程仓储」保存时会自动做这件事（`lib/data/asset_split.dart`）：

1. 把超过 **48 KB** 的资源（立绘 / 视频 / 背景图）抽出来；
2. 内容哈希作为 id（**相同图片天然去重**），存档里只留 `asset:<id>`；
3. 先 `POST /api/assets` 上传资源，再 `PUT /api/archive` 保存轻量存档；
4. 读取时 `GET /api/assets/batch?ids=...` 批量取回，再还原成 data URL；
   缺失的资源保持引用（界面显示占位符），不会白屏。

```sql
CREATE TABLE IF NOT EXISTS assets (
  id         VARCHAR(40)  NOT NULL COMMENT '内容哈希，客户端生成',
  org_id     VARCHAR(64)  NOT NULL DEFAULT 'default',
  mime       VARCHAR(64)  NOT NULL DEFAULT 'application/octet-stream',
  bytes      MEDIUMBLOB   NOT NULL COMMENT '单条最大 16MB；更大请用对象存储',
  byte_size  INT UNSIGNED NOT NULL,
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (org_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 也可只存 URL：bytes 换成 url VARCHAR(512)，图片放 COS/OSS/R2/MinIO
```

对应接口（与 `ApiClient.uploadAsset` / `fetchAssets` 一致）：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/assets?id=<id>&mime=<mime>` | body 为二进制；服务端按 (org_id,id) 去重，返回 `{"id":"..."}` |
| GET | `/api/assets/batch?ids=a,b,c` | 返回 `{"a":"<base64>","b":"<base64>"}` |

服务端片段（Node + mysql2）：

```js
app.post('/api/assets', auth, express.raw({ type: '*/*', limit: '32mb' }), async (req, res) => {
  const { id, mime = 'application/octet-stream' } = req.query;
  const buf = req.body;
  if (!id || !Buffer.isBuffer(buf)) return res.status(400).json({ error: 'bad request' });
  if (buf.length > 16 * 1024 * 1024) return res.status(413).json({ error: 'too large, use object storage' });
  await pool.query(
    `INSERT INTO assets (org_id, id, mime, bytes, byte_size) VALUES (?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE mime = VALUES(mime)`,
    [ORG, id, mime, buf, buf.length],
  );
  // 想上对象存储就这里转存，然后把 url 写回 assets.url
  res.json({ id });
});

app.get('/api/assets/batch', auth, async (req, res) => {
  const ids = String(req.query.ids || '').split(',').filter(Boolean).slice(0, 200);
  if (!ids.length) return res.json({});
  const [rows] = await pool.query(
    `SELECT id, bytes FROM assets WHERE org_id = ? AND id IN (${ids.map(() => '?').join(',')})`,
    [ORG, ...ids],
  );
  res.json(Object.fromEntries(rows.map((r) => [r.id, r.bytes.toString('base64')])));
});
```

### 方案 C：对象存储（视频多 / 人多时）

- 图片/视频放 COS / OSS / Cloudflare R2 / 自建 MinIO，DB 只存 URL；
- 客户端把 `asset:<id>` 换成 `https://cdn.你的域名/<id>.jpg` 即可（`restoreAssets` 支持直接透传 URL）；
- 好处：数据库备份再也不含几百 MB 二进制，CDN 还能加速手机端加载。

---

## 7. 服务器怎么买（按人数选）

### 画像：几十人用、图片为主

| 方案 | 配置 | 价格区间 | 说明 |
| --- | --- | --- | --- |
| 国内轻量（推荐） | 腾讯云轻量 / 阿里云 ECS 2C2G，3–5 Mbps，60–80 GB SSD | ¥60–120/月（学生机 ¥10/月） | 同机跑 MySQL 8 + Node + Caddy，够 50 人用 |
| 国内云数据库 | 腾讯云 MySQL 基础版 1C1G | ¥30–80/月 | 想省心、要自动备份就加这个；否则同机自建即可 |
| 对象存储 | 腾讯云 COS 标准 ¥0.099/GB/月，外网流量 ¥0.5/GB | 按量 | 视频走这里，图片可继续放 DB |
| 海外便宜 | Hetzner CX22（2C4G）≈ €4/月；Vultr/DO $6/月 | ¥30–50/月 | 不用备案，但国内访问慢，需套 CDN |
| 海外免备案 + 免流量费 | Cloudflare R2（$0.015/GB/月，出网免费）+ Workers | 近乎免费 | 视频/图片都放这，DB 仍在服务器上 |

**建议的起步组合**：1 台 **2C2G 轻量应用服务器**（¥60–100/月）跑 MySQL + API + Caddy（自动 HTTPS），
图片直接进 `assets` 表，视频放 COS/R2；等图片超过 2–3 GB 再把图片也搬到对象存储 + CDN。

### 备案与域名

- 国内服务器 + 80/443 端口 → 域名需 **ICP 备案**（约 1–2 周，免费）；
- 不想备案：用非 80/443 端口 + IP 访问，或买香港/海外节点，或用 Cloudflare Tunnel 反代。

### 部署清单

```bash
# 1) MySQL：装好、建库、放开包体上限
sudo apt install -y mysql-server
sudo sed -i 's/^# *max_allowed_packet.*/max_allowed_packet = 64M/' /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql

# 2) 初始化表（本文 schema.sql 段落）
mysql -u root -p < schema.sql

# 3) 跑 API（Node 20）
pm2 start server/index.js --name luoyunzong-api
pm2 save

# 4) Caddy 自动 HTTPS（只需一行）
echo 'api.你的域名.com { reverse_proxy 127.0.0.1:8080 }' | sudo tee /etc/caddy/Caddyfile
sudo systemctl reload caddy

# 5) 每天备份（存档 + 资源表），并同步到对象存储
mysqldump --single-transaction luoyunzong | gzip > /backup/lyz-$(date +%F).sql.gz
```

客户端「设置 → 数据源」填 `https://api.你的域名.com` 与访问令牌，点「保存并测试连接」即可切换到云端；
断网时 `ApiRepository` 会自动回落本地存档，不会丢数据。
