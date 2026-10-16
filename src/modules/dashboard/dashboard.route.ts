import type { FastifyPluginAsync } from "fastify";
import type { SessionStore } from "../../stores/session.store.js";
import { requireSession } from "../auth/session.guard.js";
import { DashboardController } from "./dashboard.controller.js";
import { DashboardService, type DashboardStores } from "./dashboard.service.js";

interface DashboardRoutesOptions extends DashboardStores {
  sessionStore: SessionStore;
}

// Every route acts only on the account the session belongs to.
export const dashboardRoutes: FastifyPluginAsync<DashboardRoutesOptions> = async (
  app,
  options,
) => {
  const service = new DashboardService(options);
  const controller = new DashboardController(service);

  app.addHook("onRequest", requireSession(options.sessionStore));

  app.get("/account", controller.getAccount);
  app.patch("/settings", controller.updateSettings);
  app.post("/copy/start", controller.startCopy);
  app.post("/copy/stop", controller.stopCopy);
  app.get("/commands", controller.listCommands);
  app.post("/commands", controller.createCommand);
  app.get("/commands/:id", controller.getCommand);
};
