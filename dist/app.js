import Fastify from "fastify";
import { masterRoutes } from "./modules/master/master.route.js";
export function buildApp() {
    const app = Fastify({
        logger: true,
    });
    app.get("/api/health", async () => ({
        success: true,
        status: "ok",
    }));
    void app.register(masterRoutes, { prefix: "/api/master" });
    return app;
}
//# sourceMappingURL=app.js.map