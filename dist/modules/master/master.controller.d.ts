import type { FastifyReply, FastifyRequest } from "fastify";
import type { MasterService } from "./master.service.js";
export declare class MasterController {
    private readonly service;
    constructor(service: MasterService);
    updateState: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
    getState: (_request: FastifyRequest, reply: FastifyReply) => Promise<void>;
}
//# sourceMappingURL=master.controller.d.ts.map