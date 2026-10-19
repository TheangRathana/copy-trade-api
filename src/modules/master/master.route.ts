import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import type { ChangeFeed } from "../../lib/change-feed.js";
import { eaOnly } from "../../lib/ea-guard.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { AccountRepository } from "../accounts/accounts.types.js";
import { MasterController } from "./master.controller.js";
import { MasterService } from "./master.service.js";

interface MasterRoutesOptions {
  masterStore: MasterStateStore;
  accountRepository: AccountRepository;
  changeFeed: ChangeFeed;
}

export const masterRoutes: FastifyPluginAsync<MasterRoutesOptions> = async (
  app,
  { masterStore, accountRepository, changeFeed },
) => {
  const service = new MasterService(masterStore, accountRepository, changeFeed);
  const controller = new MasterController(service);

  app.addHook("onRequest", eaOnly(config.eaAllowedIps));

  app.post("/state", controller.updateState);
};
