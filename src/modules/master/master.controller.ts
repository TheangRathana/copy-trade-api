import type { FastifyReply, FastifyRequest } from "fastify";
import { masterStateSchema } from "./master.schema.js";
import type { MasterService } from "./master.service.js";

export class MasterController {
  constructor(private readonly service: MasterService) {}

  updateState = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const result = masterStateSchema.safeParse(request.body);

    if (!result.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid master state",
        issues: result.error.issues,
      });
      return;
    }

    const update = await this.service.updateState(result.data);

    if (update.status === "not_registered") {
      await reply.status(404).send({
        success: false,
        error: `Master ${result.data.accountNumber} is not registered. Add it with POST /api/admin/masters.`,
      });
      return;
    }

    if (update.status === "disabled") {
      await reply.status(403).send({
        success: false,
        error: `Master ${result.data.accountNumber} is disabled`,
      });
      return;
    }

    await reply.status(201).send({ success: true, data: update.state });
  };
}
