import type { FastifyRequest, onRequestHookHandler } from "fastify";
import type { SessionStore } from "../../stores/session.store.js";

declare module "fastify" {
  interface FastifyRequest {
    // Account the session belongs to. Set by requireSession.
    sessionAccount: string;
    sessionToken: string;
  }
}

export function bearerToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;

  if (header === undefined || !header.startsWith("Bearer ")) {
    return null;
  }

  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

// buildApp registers the request decorators this hook fills in.
export function requireSession(sessions: SessionStore): onRequestHookHandler {
  return async (request, reply) => {
    const token = bearerToken(request);
    const account = token === null ? null : sessions.resolve(token);

    if (token === null || account === null) {
      return reply.status(401).send({ success: false, error: "Unauthorized" });
    }

    request.sessionAccount = account;
    request.sessionToken = token;
  };
}
