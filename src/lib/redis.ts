import { Redis } from "ioredis";

// Every key this API writes starts with "ct:" (copy trade), so it can share a
// Redis server with other apps. The database number comes from the URL path.
export const REDIS_KEY_PREFIX = "ct:";

// rediss:// (TLS, as DigitalOcean Managed Redis requires) is handled by ioredis.
export function createRedis(url: string): Redis {
  return new Redis(url, {
    keyPrefix: REDIS_KEY_PREFIX,
    // Fail a request after a few tries instead of queueing it forever
    maxRetriesPerRequest: 3,
    connectTimeout: 10_000,
  });
}

// For the health check: true when Redis answers within timeoutMs
export async function redisReachable(redis: Redis, timeoutMs = 2000): Promise<boolean> {
  try {
    const reply = await Promise.race([
      redis.ping(),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), timeoutMs)),
    ]);
    return reply === "PONG";
  } catch {
    return false;
  }
}
