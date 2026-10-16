import type { FastifyReply, FastifyRequest } from "fastify";
import { copySettingsPatchSchema } from "../settings/settings.schema.js";
import {
  commandParamsSchema,
  createCommandSchema,
  stopCopySchema,
} from "./dashboard.schema.js";
import type { DashboardService } from "./dashboard.service.js";

export class DashboardController {
  constructor(private readonly service: DashboardService) {}

  getAccount = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    await reply.send({
      success: true,
      data: this.service.getAccount(request.sessionAccount),
    });
  };

  updateSettings = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const patch = copySettingsPatchSchema.safeParse(request.body);

    if (!patch.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid settings",
        issues: patch.error.issues,
      });
      return;
    }

    const result = this.service.updateSettings(request.sessionAccount, patch.data);

    if (!result.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid settings",
        issues: result.issues,
      });
      return;
    }

    await reply.send({ success: true, data: result.data });
  };

  startCopy = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    await reply.send({
      success: true,
      data: this.service.startCopy(request.sessionAccount),
    });
  };

  stopCopy = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const result = stopCopySchema.safeParse(request.body ?? {});

    if (!result.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid stop request",
        issues: result.error.issues,
      });
      return;
    }

    await reply.send({
      success: true,
      data: this.service.stopCopy(request.sessionAccount, result.data.closeAll),
    });
  };

  createCommand = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const input = createCommandSchema.safeParse(request.body);

    if (!input.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid command",
        issues: input.error.issues,
      });
      return;
    }

    const result = this.service.createCommand(request.sessionAccount, input.data);

    if (result.status === "offline") {
      await reply.status(409).send({
        success: false,
        error: "Terminal is offline",
      });
      return;
    }

    if (result.status === "position_not_found") {
      await reply.status(404).send({
        success: false,
        error: "Position not found",
      });
      return;
    }

    await reply.status(202).send({ success: true, data: result.command });
  };

  getCommand = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    const params = commandParamsSchema.safeParse(request.params);
    const command = params.success
      ? this.service.getCommand(request.sessionAccount, params.data.id)
      : null;

    if (command === null) {
      await reply.status(404).send({
        success: false,
        error: "Command not found",
      });
      return;
    }

    await reply.send({ success: true, data: command });
  };

  listCommands = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    await reply.send({
      success: true,
      data: this.service.listCommands(request.sessionAccount),
    });
  };
}
