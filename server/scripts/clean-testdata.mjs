// 清理测试数据（探针跑完后用）。
// 用法：node scripts/clean-testdata.mjs
import 'dotenv/config';
import { pool } from '../db.mjs';

const [a] = await pool.query('DELETE FROM archives');
const [b] = await pool.query('DELETE FROM assets');
console.log(`[clean] archives ${a.affectedRows} 行, assets ${b.affectedRows} 行`);
await pool.end();
