-- 落云宗 · 云同步服务端表结构（Aiven MySQL 8.x / 自建 MySQL 5.7+ 均可）
-- 用法：mysql -h <host> -P <port> -u <user> -p < schema.sql
--      或 node scripts/apply-schema.mjs（会自动建库/建表）

CREATE TABLE IF NOT EXISTS archives (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id          VARCHAR(64)  NOT NULL DEFAULT 'default' COMMENT '宗门标识',
  archive_version INT          NOT NULL DEFAULT 4,
  payload         LONGTEXT     NOT NULL COMMENT 'Archive.toJson() 的 JSON（大资源存 asset:<id> 引用）',
  revision        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_by      VARCHAR(64)  NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_org (org_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 资源表：头像 / 立绘 / 背景图 / 动态视频的字节或外部 URL
CREATE TABLE IF NOT EXISTS assets (
  id         VARCHAR(64)  NOT NULL COMMENT '内容哈希，客户端生成',
  org_id     VARCHAR(64)  NOT NULL DEFAULT 'default',
  mime       VARCHAR(64)  NOT NULL DEFAULT 'application/octet-stream',
  byte_size  INT UNSIGNED NOT NULL DEFAULT 0,
  bytes      MEDIUMBLOB   NULL COMMENT '存 DB 时的字节（单条 <=16MB）',
  url        VARCHAR(512) NULL COMMENT '存对象存储时的公开 URL',
  driver     VARCHAR(16)  NOT NULL DEFAULT 'local' COMMENT 'local | upyun | s3',
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (org_id, id),
  KEY idx_org_created (org_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 管理员（可选：把管理员密码放到服务端校验，替代存档里的明文密码）
CREATE TABLE IF NOT EXISTS admins (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id        VARCHAR(64) NOT NULL DEFAULT 'default',
  username      VARCHAR(64) NOT NULL,
  password_hash VARCHAR(255) NOT NULL COMMENT 'bcrypt / argon2 哈希',
  role          ENUM('owner','admin','viewer') NOT NULL DEFAULT 'admin',
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_org_user (org_id, username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 操作审计（可选）
CREATE TABLE IF NOT EXISTS audit_logs (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  org_id     VARCHAR(64) NOT NULL DEFAULT 'default',
  actor      VARCHAR(64) NULL,
  action     VARCHAR(64) NOT NULL,
  detail     TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_org_time (org_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 服务端运行配置（管理员在 App 里改，存这里；例如对象存储的缤纷云密钥）
-- 注意：这些值不进存档、不随云同步回客户端，只在服务端使用。
CREATE TABLE IF NOT EXISTS app_settings (
  org_id     VARCHAR(64) NOT NULL DEFAULT 'default',
  skey       VARCHAR(64) NOT NULL COMMENT '配置名，例如 storage',
  svalue     TEXT        NULL COMMENT 'JSON 文本',
  updated_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (org_id, skey)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
