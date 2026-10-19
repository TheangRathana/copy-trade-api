import type { FastifyPluginAsync } from "fastify";
import type { SessionStore } from "../../stores/session.store.js";
import { jsonSchema, SESSION_SECURITY, TAGS } from "../../lib/openapi.js";
import { requireSession } from "../auth/session.guard.js";
import { copySettingsPatchSchema } from "../settings/settings.schema.js";
import {
  commandParamsSchema,
  createCommandSchema,
  stopCopySchema,
} from "./dashboard.schema.js";
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

  const docs = (summary: string, extra: Record<string, unknown> = {}) => ({
    schema: { tags: [TAGS.dashboard], summary, security: SESSION_SECURITY, ...extra },
  });

  app.get(
    "/account",
    docs("Account status, positions, copy state, settings and lot size"),
    controller.getAccount,
  );
  app.patch(
    "/settings",
    docs("Change copy and risk settings (any subset)", {
      description: "Lot size is not here: it is set in the follower EA's MT5 inputs.",
      body: jsonSchema(copySettingsPatchSchema),
    }),
    controller.updateSettings,
  );
  app.post("/copy/start", docs("Start copying"), controller.startCopy);
  app.post(
    "/copy/stop",
    docs("Stop copying, optionally closing all copied trades", {
      body: jsonSchema(stopCopySchema),
    }),
    controller.stopCopy,
  );
  app.get("/commands", docs("Recent commands, newest first"), controller.listCommands);
  app.post(
    "/commands",
    docs("Close one position or all copied positions", {
      description: "Runs on the EA within milliseconds; 409 while the terminal is offline.",
      body: jsonSchema(createCommandSchema),
    }),
    controller.createCommand,
  );
  app.get(
    "/commands/:id",
    docs("One command's status", { params: jsonSchema(commandParamsSchema) }),
    controller.getCommand,
  );
};
