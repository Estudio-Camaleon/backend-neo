import { query } from "./db";

const memoryStore = new Map<string, { count: number; expiresAt: number }>();

const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;
let lastCleanup = Date.now();

async function cleanupExpiredEntries() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL_MS) return;
  lastCleanup = now;

  try {
    await query("DELETE FROM rate_limits WHERE expires_at < NOW()");
  } catch {
    // cleanup failure is non-critical
  }

  for (const [key, entry] of memoryStore) {
    if (entry.expiresAt < now) memoryStore.delete(key);
  }
}

export async function checkRateLimit(
  key: string,
  maxAttempts = 10,
  windowMs = 60000
): Promise<boolean> {
  const now = Date.now();

  try {
    await cleanupExpiredEntries();

    const expiresAt = new Date(now + windowMs).toISOString().slice(0, 19).replace("T", " ");

    const { rows: existing } = await query(
      "SELECT `count` FROM rate_limits WHERE `key` = ? AND expires_at >= NOW() LIMIT 1",
      [key]
    );

    if (!existing[0]) {
      await query(
        "INSERT INTO rate_limits (id, `key`, `count`, expires_at) VALUES (UUID(), ?, 1, ?)",
        [key, expiresAt]
      );
      return true;
    }

    if (existing[0].count >= maxAttempts) {
      return false;
    }

    await query(
      "UPDATE rate_limits SET `count` = `count` + 1 WHERE `key` = ?",
      [key]
    );

    return true;
  } catch {
    const entry = memoryStore.get(key);
    if (!entry || entry.expiresAt < now) {
      memoryStore.set(key, { count: 1, expiresAt: now + windowMs });
      return true;
    }

    if (entry.count >= maxAttempts) {
      return false;
    }

    entry.count++;
    return true;
  }
}
