// 查看云端数据（存档 + 资源表），并支持清理测试数据。
// 用法：
//   node scripts/inspect.mjs            查看概览
//   node scripts/inspect.mjs --clean     删除测试用的 org（__check__）与本地测试资源
import 'dotenv/config';
import { pool, ORG_ID } from '../db.mjs';

const clean = process.argv.includes('--clean');

async function main() {
  const [archives] = await pool.query(
    'SELECT org_id, revision, LENGTH(payload) AS bytes, updated_at FROM archives ORDER BY updated_at DESC',
  );
  console.log('[inspect] 存档表:');
  for (const a of archives) {
    console.log(`  · org=${a.org_id} revision=${a.revision} 大小=${(a.bytes / 1024).toFixed(1)}KB 更新=${a.updated_at}`);
  }

  const [assets] = await pool.query(
    `SELECT driver, COUNT(*) AS n, ROUND(SUM(byte_size)/1024, 1) AS kb
       FROM assets WHERE org_id = ? GROUP BY driver`,
    [ORG_ID],
  );
  console.log('[inspect] 资源表（按驱动统计）:');
  for (const a of assets) console.log(`  · ${a.driver}: ${a.n} 个，共 ${a.kb} KB`);

  const [recent] = await pool.query(
    'SELECT id, mime, byte_size, driver, url, created_at FROM assets WHERE org_id = ? ORDER BY created_at DESC LIMIT 5',
    [ORG_ID],
  );
  console.log('[inspect] 最近 5 个资源:');
  for (const r of recent) {
    console.log(`  · ${r.id} ${r.mime} ${r.byte_size}B ${r.driver} ${r.url || '(本地)'} ${r.created_at}`);
  }

  const [usage] = await pool.query(
    `SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS mb
       FROM information_schema.tables WHERE table_schema = DATABASE()`,
  );
  console.log(`[inspect] 数据库总占用: ${usage[0].mb} MB（Aiven 免费版 1GB）`);

  if (clean) {
    const [res1] = await pool.query("DELETE FROM archives WHERE org_id LIKE '__%'");
    const [res2] = await pool.query('DELETE FROM assets WHERE id LIKE ?', ['testasset%']);
    console.log(`[inspect] 已清理: archives ${res1.affectedRows} 行, assets ${res2.affectedRows} 行`);
  }
  await pool.end();
}

main().catch(async (err) => {
  console.error('[inspect] 失败:', err.message);
  try {
    await pool.end();
  } catch {}
  process.exit(1);
});
