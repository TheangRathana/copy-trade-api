import { createHash, timingSafeEqual } from "node:crypto";
import type { FastifyRequest, onRequestHookHandler } from "fastify";

// Set by a reverse proxy or tunnel. A Cloudflare Tunnel connects from the VPS
// itself, so tunnelled internet traffic arrives from 127.0.0.1; these headers
// are what tell it apart from an EA on the same machine.
const PROXY_HEADERS = ["cf-connecting-ip", "x-forwarded-for", "x-real-ip", "forwarded"];

export const EA_KEY_HEADER = "x-ea-key";

export function isProxied(request: FastifyRequest): boolean {
  return PROXY_HEADERS.some((header) => request.headers[header] !== undefined);
}

const digest = (value: string) => createHash("sha256").update(value).digest();

function hasEaKey(request: FastifyRequest, eaApiKey: string): boolean {
  const sent = request.headers[EA_KEY_HEADER];
  // Compare hashes so the check takes the same time for any wrong key
  return typeof sent === "string" && timingSafeEqual(digest(sent), digest(eaApiKey));
}

// EA endpoints accept:
// - an EA that sends the EA_API_KEY in the X-EA-Key header, from anywhere
//   (EAs on another machine, through nginx / HTTPS), or
// - an EA on the same machine (allowed IP, not through a proxy).
export function eaOnly(
  allowedIps: readonly string[],
  eaApiKey: string | null,
): onRequestHookHandler {
  return async (request, reply) => {
    if (eaApiKey !== null && hasEaKey(request, eaApiKey)) {
      return;
    }

    const allowedIp = allowedIps.includes("*") || allowedIps.includes(request.ip);

    if (allowedIp && !isProxied(request)) {
      return;
    }

    return reply.status(403).send({ success: false, error: "Forbidden" });
  };
}
