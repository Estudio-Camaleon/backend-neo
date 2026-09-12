import mysql from "mysql2/promise";

const config = {
  uri: process.env.DATABASE_URL || "mysql://neo:neo_secret@db:3306/neo",
  waitForConnections: true,
  connectionLimit: 20,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0,
};

export const pool = mysql.createPool(config);

pool.on("connection", () => {
  console.log("[DB] New connection established");
});

export async function query<T = any>(
  sql: string,
  params?: any[]
): Promise<{ rows: T[]; rowCount: number; insertId?: number; affectedRows?: number }> {
  const start = Date.now();
  const [rows] = await pool.execute(sql, params);
  const duration = Date.now() - start;
  if (duration > 500) {
    console.warn(`[DB] Slow query (${duration}ms):`, sql.slice(0, 100));
  }

  const result = rows as any;
  if (Array.isArray(result)) {
    return { rows: result as T[], rowCount: result.length };
  }

  return {
    rows: [],
    rowCount: result.affectedRows || 0,
    insertId: result.insertId,
    affectedRows: result.affectedRows,
  };
}
