import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import { eaOnly } from "../../lib/ea-guard.js";
import { FollowerController } from "./follower.controller.js";
import { FollowerService, type FollowerStores } from "./follower.service.js";

export const followerRoutes: FastifyPluginAsync<FollowerStores> = async (
  app,
  stores,
) => {
  const service = new FollowerService(stores);
  const controller = new FollowerController(service);

  app.addHook("onRequest", eaOnly(config.eaAllowedIps));

  app.post("/sync", controller.sync);
  app.post("/commands/:id/ack", controller.ackCommand);
};
