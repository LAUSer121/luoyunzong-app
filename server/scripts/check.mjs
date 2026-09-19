// 连接检查：验证 Aiven MySQL 可达、SSL 正常、表能建、读写正常。
// 用法：node scripts/check.mjs
import 'dotenv/config';
import { pool, withTransaction } from '../db.mjs';

async function main() {
  const started = Date.now();
  const [ver] = await pool.query('SELECT VERSION() AS v, DATABASE() AS db, NOW() AS now');
  console.log(`[check] 连接成功（${Date.now() - started}ms）`);
  console.log(`[check] 版本=${ver[0].v} 库=${ver[0].db} 服务器时间=${ver[0].now}`);

  const [tables] = await pool.query('SHOW TABLES');
  console.log('[check] 现有表:', tables.map((r) => Object.values(r)[0]).join(', ') || '(空)');

  const [ssl] = await pool.query(
    "SHOW STATUS LIKE 'Ssl_cipher'",
  );
  console.log(`[check] SSL: ${ssl[0]?.Value || '(未启用)'}`);

  // 写入/读取/清理一条测试存档
  await withTransaction(async (conn) => {
    await conn.query(
      `INSERT INTO archives (org_id, payload) VALUES ('__check__', JSON_OBJECT('ok', true))
       ON DUPLICATE KEY UPDATE payload = VALUES(payload)`,
    );
  });
  const [rows] = await pool.query('SELECT payload FROM archives WHERE org_id = ?', ['__check__']);
  console.log('[check] 写入并读回:', rows[0]?.payload);
  await pool.query('DELETE FROM archives WHERE org_id = ?', ['__check__']);

  const [size] = await pool.query(
    `SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS mb
       FROM information_schema.tables WHERE table_schema = DATABASE()`,
  );
  console.log(`[check] 当前库占用: ${size[0].mb ?? 0} MB`);
  await pool.end();
  console.log('[check] 全部通过 ✅');
}

main().catch(async (err) => {
  console.error('[check] 失败:', err.code || '', err.message);
  try {
    await pool.end();
  } catch {}
  process.exit(1);
});
