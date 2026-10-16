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
  await app.register(rateLimit, { global: false });

  app.post(
    "/login",
    { config: { rateLimit: { max: 20, timeWindow: "1 minute" } } },
    controller.login,
  );
  app.post("/logout", { onRequest: sessionGuard }, controller.logout);
  app.post("/logout-all", { onRequest: sessionGuard }, controller.logoutAll);
};
