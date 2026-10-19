import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import { ADMIN_SECURITY, jsonSchema, TAGS } from "../../lib/openapi.js";
import {
  accountParamsSchema,
  createFollowerSchema,
  createMasterSchema,
  listFollowersQuerySchema,
  updateFollowerSchema,
  updateMasterSchema,
} from "../accounts/accounts.schema.js";
import { AdminController } from "./admin.controller.js";
import { requireAdmin } from "./admin.guard.js";
import { AdminService, type AdminStores } from "./admin.service.js";

// Managing masters and followers ("account 1 follows master A"). Needs the
// ADMIN_API_KEY bearer key.
export const adminRoutes: FastifyPluginAsync<AdminStores> = async (app, stores) => {
  const service = new AdminService(stores);
  const controller = new AdminController(service);

  app.addHook("onRequest", requireAdmin(config.adminApiKey));

  const docs = (summary: string, extra: Record<string, unknown> = {}) => ({
    schema: { tags: [TAGS.admin], summary, security: ADMIN_SECURITY, ...extra },
  });
  const params = jsonSchema(accountParamsSchema);

  app.get("/masters", docs("List masters, with online status and follower count"), controller.listMasters);
  app.post(
    "/masters",
    docs("Add a master", { body: jsonSchema(createMasterSchema) }),
    controller.createMaster,
  );
  app.get("/masters/:account", docs("One master and its followers", { params }), controller.getMaster);
  app.patch(
    "/masters/:account",
    docs("Rename, add a note, or enable/disable a master", {
      description: "`enabled: false` stops its followers receiving its trades.",
      params,
      body: jsonSchema(updateMasterSchema),
    }),
    controller.updateMaster,
  );
  app.delete(
    "/masters/:account",
    docs("Delete a master", { description: "409 while it still has followers.", params }),
    controller.deleteMaster,
  );

  app.get(
    "/followers",
    docs("List followers, or one master's followers", {
      querystring: jsonSchema(listFollowersQuerySchema),
    }),
    controller.listFollowers,
  );
  app.post(
    "/followers",
    docs("Add a follower and the master it copies", { body: jsonSchema(createFollowerSchema) }),
    controller.createFollower,
  );
  app.get(
    "/followers/:account",
    docs("One follower, with its settings, lot size and status", { params }),
    controller.getFollower,
  );
  app.patch(
    "/followers/:account",
    docs("Rename, add a note, or move a follower to another master", {
      params,
      body: jsonSchema(updateFollowerSchema),
    }),
    controller.updateFollower,
  );
  app.delete(
    "/followers/:account",
    docs("Delete a follower", {
      description: "Also removes its settings and logs out its dashboard sessions.",
      params,
    }),
    controller.deleteFollower,
  );
};
