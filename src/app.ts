import Fastify, { type FastifyInstance } from "fastify";
import { config } from "./config.js";
import { authRoutes } from "./modules/auth/auth.route.js";
import { dashboardRoutes } from "./modules/dashboard/dashboard.route.js";
import { followerRoutes } from "./modules/follower/follower.route.js";
import { masterRoutes } from "./modules/master/master.route.js";
import { adminRoutes } from "./modules/admin/admin.route.js";
import { FileAccountRepository } from "./stores/account.repository.js";
import { ChangeFeed } from "./lib/change-feed.js";
import { CommandStore } from "./stores/command.store.js";
import { FollowerStore } from "./stores/follower.store.js";
import { MasterStateStore } from "./stores/master-state.store.js";
import { PairingStore } from "./stores/pairing.store.js";
import { SessionStore } from "./stores/session.store.js";
import { SettingsStore } from "./stores/settings.store.js";

export function buildApp(): FastifyInstance {
  const app = Fastify({
    logger: true,
  });

  const stores = {
    masterStore: new MasterStateStore(),
    followerStore: new FollowerStore(),
    settingsStore: new SettingsStore(config.dataDir),
    commandStore: new CommandStore({
      ttlMs: config.commandTtlMs,
      historyMs: config.commandHistoryMs,
    }),
    pairingStore: new PairingStore({
      ttlMs: config.pairingCodeTtlMs,
      maxAttempts: config.pairingMaxAttempts,
      lockMs: config.pairingLockMs,
    }),
    sessionStore: new SessionStore(config.dataDir, config.sessionTtlMs),
    changeFeed: new ChangeFeed(),
    // Swap for the Redis repository once Redis is connected
    accountRepository: new FileAccountRepository(config.dataDir),
  };

  app.decorateRequest("sessionAccount", "");
  app.decorateRequest("sessionToken", "");

  app.get("/api/health", async () => ({
    success: true,
    status: "ok",
  }));

  // EA endpoints (localhost only).
  void app.register(masterRoutes, { prefix: "/api/master", ...stores });
  void app.register(followerRoutes, { prefix: "/api/follower", ...stores });

  // Admin: manage masters and followers (ADMIN_API_KEY)
  void app.register(adminRoutes, { prefix: "/api/admin", ...stores });

  // UI endpoints (called by the Next.js server).
  void app.register(authRoutes, { prefix: "/api/auth", ...stores });
  void app.register(dashboardRoutes, { prefix: "/api/dashboard", ...stores });

  return app;
}
