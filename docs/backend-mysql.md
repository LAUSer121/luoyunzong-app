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
