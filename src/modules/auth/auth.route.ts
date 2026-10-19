import rateLimit from "@fastify/rate-limit";
import type { FastifyPluginAsync } from "fastify";
import { AuthController } from "./auth.controller.js";
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
    { config: { rateLimit: { max: 20, timeWindow: "1 minute" } } },
    controller.login,
  );
  app.post("/logout", { onRequest: sessionGuard }, controller.logout);
  app.post("/logout-all", { onRequest: sessionGuard }, controller.logoutAll);
};
