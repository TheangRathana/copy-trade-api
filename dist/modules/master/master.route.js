import { MasterStateStore } from "../../stores/master-state.store.js";
import { MasterController } from "./master.controller.js";
import { MasterService } from "./master.service.js";
export const masterRoutes = async (app) => {
    const store = new MasterStateStore();
    const service = new MasterService(store);
    const controller = new MasterController(service);
    app.post("/state", controller.updateState);
    app.get("/state", controller.getState);
};
//# sourceMappingURL=master.route.js.map