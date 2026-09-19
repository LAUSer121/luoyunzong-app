// 建表脚本：读取 schema.sql 逐条执行（幂等）。
// 用法：node scripts/apply-schema.mjs
import 'dotenv/config';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { pool } from '../db.mjs';

const sqlPath = fileURLToPath(new URL('../schema.sql', import.meta.url));

async function main() {
  const raw = fs.readFileSync(sqlPath, 'utf8');
  const statements = raw
    .split(/;\s*\n/)
    .map((s) => s.replace(/^\s*--.*$/gm, '').trim())
    .filter((s) => s.length > 0);

  for (const statement of statements) {
    await pool.query(statement);
    const first = statement.split('\n')[0].slice(0, 60);
    console.log(`[schema] ok: ${first}…`);
  }
  const [tables] = await pool.query('SHOW TABLES');
  console.log('[schema] 当前表:', tables.map((r) => Object.values(r)[0]).join(', '));
  await pool.end();
}

main().catch(async (err) => {
  console.error('[schema] 失败:', err.message);
  try {
    await pool.end();
  } catch {}
  process.exit(1);
});
