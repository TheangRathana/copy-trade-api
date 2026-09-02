import { masterStateSchema } from "./master.schema.js";
export class MasterController {
    service;
    constructor(service) {
        this.service = service;
    }
    updateState = async (request, reply) => {
        const result = masterStateSchema.safeParse(request.body);
        if (!result.success) {
            await reply.status(400).send({
                success: false,
                error: "Invalid master state",
                issues: result.error.issues,
            });
            return;
        }
        const state = this.service.updateState(result.data);
        await reply.status(201).send({ success: true, data: state });
    };
    getState = async (_request, reply) => {
        const state = this.service.getLatestState();
        if (state === null) {
            await reply.status(404).send({
                success: false,
                error: "Master state not found",
            });
            return;
        }
        await reply.send({ success: true, data: state });
    };
}
//# sourceMappingURL=master.controller.js.map