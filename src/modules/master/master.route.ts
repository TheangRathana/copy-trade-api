import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import { eaOnly } from "../../lib/ea-guard.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import { MasterController } from "./master.controller.js";
import { MasterService } from "./master.service.js";

interface MasterRoutesOptions {
  masterStore: MasterStateStore;
}

export const masterRoutes: FastifyPluginAsync<MasterRoutesOptions> = async (
  app,
  { masterStore },
) => {
  const service = new MasterService(masterStore);
  const controller = new MasterController(service);

  app.addHook("onRequest", eaOnly(config.eaAllowedIps));

  app.post("/state", controller.updateState);
  app.get("/state", controller.getState);
};
