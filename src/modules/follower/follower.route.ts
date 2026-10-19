import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import { eaOnly } from "../../lib/ea-guard.js";
import { jsonSchema, TAGS } from "../../lib/openapi.js";
import {
  commandAckParamsSchema,
  commandAckSchema,
  followerSyncSchema,
} from "./follower.schema.js";
import { FollowerController } from "./follower.controller.js";
import { FollowerService, type FollowerStores } from "./follower.service.js";

export const followerRoutes: FastifyPluginAsync<FollowerStores> = async (
  app,
  stores,
) => {
  const service = new FollowerService(stores);
  const controller = new FollowerController(service);

  app.addHook("onRequest", eaOnly(config.eaAllowedIps));

  app.post(
    "/sync",
    {
      schema: {
        tags: [TAGS.ea],
        summary: "Follower EA reports its status and gets what it needs",
        description:
          "Returns its master's positions, copy settings, pending commands and the " +
          "dashboard pairing code. Long polling: with `knownMasterVersion` and `waitMs`, an " +
          "up-to-date follower is held until something changes or `waitMs` passes.",
        body: jsonSchema(followerSyncSchema),
      },
    },
    controller.sync,
  );
  app.post(
    "/commands/:id/ack",
    {
      schema: {
        tags: [TAGS.ea],
        summary: "Follower EA reports a command result",
        params: jsonSchema(commandAckParamsSchema),
        body: jsonSchema(commandAckSchema),
      },
    },
    controller.ackCommand,
  );
};
