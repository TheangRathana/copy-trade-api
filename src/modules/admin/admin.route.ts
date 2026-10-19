import type { FastifyPluginAsync } from "fastify";
import { config } from "../../config.js";
import { AdminController } from "./admin.controller.js";
import { requireAdmin } from "./admin.guard.js";
import { AdminService, type AdminStores } from "./admin.service.js";

// Managing masters and followers ("account 1 follows master A"). Needs the
// ADMIN_API_KEY bearer key.
export const adminRoutes: FastifyPluginAsync<AdminStores> = async (app, stores) => {
  const service = new AdminService(stores);
  const controller = new AdminController(service);

  app.addHook("onRequest", requireAdmin(config.adminApiKey));

  app.get("/masters", controller.listMasters);
  app.post("/masters", controller.createMaster);
  app.get("/masters/:account", controller.getMaster);
  app.patch("/masters/:account", controller.updateMaster);
  app.delete("/masters/:account", controller.deleteMaster);

  app.get("/followers", controller.listFollowers);
  app.post("/followers", controller.createFollower);
  app.get("/followers/:account", controller.getFollower);
  app.patch("/followers/:account", controller.updateFollower);
  app.delete("/followers/:account", controller.deleteFollower);
};
