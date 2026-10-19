import type { FastifyReply, FastifyRequest } from "fastify";
import {
  commandAckParamsSchema,
  commandAckSchema,
  followerSyncSchema,
} from "./follower.schema.js";
import type { FollowerService } from "./follower.service.js";

export class FollowerController {
  constructor(private readonly service: FollowerService) {}

  sync = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const result = followerSyncSchema.safeParse(request.body);

    if (!result.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid follower sync",
        issues: result.error.issues,
      });
      return;
    }

    await reply.send({ success: true, data: await this.service.sync(result.data) });
  };

  ackCommand = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const params = commandAckParamsSchema.safeParse(request.params);
    const body = commandAckSchema.safeParse(request.body);

    if (!params.success || !body.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid command ack",
        issues: [
          ...(params.error?.issues ?? []),
          ...(body.error?.issues ?? []),
        ],
      });
      return;
    }

    const command = this.service.ackCommand(params.data.id, body.data);

    if (command === null) {
      await reply.status(404).send({
        success: false,
        error: "Command not found",
      });
      return;
    }

    await reply.send({ success: true, data: command });
  };
}
