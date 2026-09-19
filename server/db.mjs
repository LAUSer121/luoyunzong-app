// Aiven MySQL 连接池（免费版要求 SSL，这里默认开启）
import 'dotenv/config';
import mysql from 'mysql2/promise';
import fs from 'node:fs';

const useSsl = String(process.env.DB_SSL ?? 'true').toLowerCase() !== 'false';

/** Aiven 控制台可下载 CA 证书；放到 server/ca.pem 即自动启用校验 */
function sslConfig() {
  if (!useSsl) return undefined;
  const caPath = process.env.DB_CA_PATH || new URL('ca.pem', import.meta.url).pathname;
  try {
    if (caPath && fs.existsSync(caPath)) {
      return { ca: fs.readFileSync(caPath), rejectUnauthorized: true };
    }
  } catch {
    // 忽略，落到宽松模式
  }
  // 未放 CA 时仍走 TLS，但不校验证书链（Aiven 默认配置下可用）
  return { rejectUnauthorized: false };
}

export const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'defaultdb',
  waitForConnections: true,
  connectionLimit: Number(process.env.DB_POOL || 8),
  charset: 'utf8mb4',
  timezone: 'Z',
  ssl: sslConfig(),
  multipleStatements: false,
});

/** 简单事务包装 */
export async function withTransaction(fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const out = await fn(conn);
    await conn.commit();
    return out;
  } catch (err) {
    try {
      await conn.rollback();
    } catch {}
    throw err;
  } finally {
    conn.release();
  }
}

export const ORG_ID = process.env.ORG_ID || 'default';
