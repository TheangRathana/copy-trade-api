import type { FastifyRequest, onRequestHookHandler } from "fastify";

// Set by a reverse proxy or tunnel. A Cloudflare Tunnel connects from the VPS
// itself, so tunnelled internet traffic arrives from 127.0.0.1; these headers
// are what tell it apart from an EA on the same machine.
const PROXY_HEADERS = ["cf-connecting-ip", "x-forwarded-for", "x-real-ip", "forwarded"];

export function isProxied(request: FastifyRequest): boolean {
  return PROXY_HEADERS.some((header) => request.headers[header] !== undefined);
}

// EA endpoints are only for terminals running on the same VPS.
export function eaOnly(allowedIps: readonly string[]): onRequestHookHandler {
  return async (request, reply) => {
    const allowedIp = allowedIps.includes("*") || allowedIps.includes(request.ip);

    if (allowedIp && !isProxied(request)) {
      return;
    }

    return reply.status(403).send({ success: false, error: "Forbidden" });
  };
}
