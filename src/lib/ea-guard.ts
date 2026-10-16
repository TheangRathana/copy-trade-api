import type { onRequestHookHandler } from "fastify";

// EA endpoints are only for terminals running on the same VPS.
export function eaOnly(allowedIps: readonly string[]): onRequestHookHandler {
  return async (request, reply) => {
    if (allowedIps.includes("*") || allowedIps.includes(request.ip)) {
      return;
    }

    return reply.status(403).send({ success: false, error: "Forbidden" });
  };
}
