import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import type { ChangeFeed } from "../../lib/change-feed.js";
import { eaOnly } from "../../lib/ea-guard.js";
import { EA_SECURITY, jsonSchema, TAGS } from "../../lib/openapi.js";
import { masterStateSchema } from "./master.schema.js";
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

  app.addHook("onRequest", eaOnly(config.eaAllowedIps, config.eaApiKey));

  app.post(
    "/state",
    {
      schema: {
        tags: [TAGS.ea],
        security: EA_SECURITY,
        summary: "Master EA posts its open positions",
        description:
          "Sent on every trade event and as a heartbeat. Only registered, enabled masters " +
          "are accepted (404 not registered, 403 disabled). A change in positions wakes " +
          "this master's waiting followers.",
        body: jsonSchema(masterStateSchema),
      },
    },
    controller.updateState,
  );
};
