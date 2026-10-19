import rateLimit from "@fastify/rate-limit";
import type { FastifyPluginAsync } from "fastify";
import { jsonSchema, SESSION_SECURITY, TAGS } from "../../lib/openapi.js";
import { AuthController } from "./auth.controller.js";
import { loginSchema } from "./auth.schema.js";
import { AuthService, type AuthStores } from "./auth.service.js";
import { requireSession } from "./session.guard.js";

export const authRoutes: FastifyPluginAsync<AuthStores> = async (
  app,
  stores,
) => {
  const service = new AuthService(stores);
  const controller = new AuthController(service);
  const sessionGuard = requireSession(stores.sessionStore);

  // Per-account lockout is the main brute-force protection; this caps volume.
  // Behind a Cloudflare Tunnel every request comes from 127.0.0.1, so limit
  // by the visitor's IP that Cloudflare passes on.
  await app.register(rateLimit, {
    global: false,
    keyGenerator: (request) => {
      const visitorIp = request.headers["cf-connecting-ip"];
      return typeof visitorIp === "string" ? visitorIp : request.ip;
    },
  });

  app.post(
    "/login",
    {
      config: { rateLimit: { max: 20, timeWindow: "1 minute" } },
      schema: {
        tags: [TAGS.auth],
        summary: "Log in with the account number and the EA's pairing code",
        description:
          "The 6-digit code is shown on the follower EA's chart; it lasts 5 minutes and works " +
          "once. 5 wrong codes lock the account for 15 minutes (429). Returns a session token.",
        body: jsonSchema(loginSchema),
      },
    },
    controller.login,
  );
  app.post(
    "/logout",
    {
      onRequest: sessionGuard,
      schema: { tags: [TAGS.auth], summary: "End this session", security: SESSION_SECURITY },
    },
    controller.logout,
  );
  app.post(
    "/logout-all",
    {
      onRequest: sessionGuard,
      schema: {
        tags: [TAGS.auth],
        summary: "End every session of this account (all devices)",
        security: SESSION_SECURITY,
      },
    },
    controller.logoutAll,
  );
};
