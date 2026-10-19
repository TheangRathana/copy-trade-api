import { createHash, timingSafeEqual } from "node:crypto";
import type { onRequestHookHandler } from "fastify";
import { bearerToken } from "../auth/session.guard.js";

const digest = (value: string) => createHash("sha256").update(value).digest();

// Admin endpoints need "Authorization: Bearer <ADMIN_API_KEY>".
export function requireAdmin(adminApiKey: string | null): onRequestHookHandler {
  return async (request, reply) => {
    if (adminApiKey === null) {
      return reply.status(503).send({
        success: false,
        error: "Admin API is off. Set ADMIN_API_KEY to turn it on.",
      });
    }

    const token = bearerToken(request);
    // Compare hashes so the check takes the same time for any wrong key
    if (token === null || !timingSafeEqual(digest(token), digest(adminApiKey))) {
      return reply.status(401).send({ success: false, error: "Unauthorized" });
    }
  };
}
