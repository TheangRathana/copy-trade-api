import type { FastifyReply, FastifyRequest } from "fastify";
import type { ZodType } from "zod";
import {
  accountParamsSchema,
  createFollowerSchema,
  createMasterSchema,
  listFollowersQuerySchema,
  updateFollowerSchema,
  updateMasterSchema,
} from "../accounts/accounts.schema.js";
import type { AdminResult, AdminService } from "./admin.service.js";

const STATUS_CODES = { not_found: 404, conflict: 409, invalid: 400 } as const;

export class AdminController {
  constructor(private readonly service: AdminService) {}

  //--- Masters -----------------------------------------------------------

  listMasters = async (_request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    await reply.send({ success: true, data: await this.service.listMasters() });
  };

  getMaster = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;

    const master = await this.service.getMaster(account);
    if (master === null) {
      await reply.status(404).send({ success: false, error: `Master ${account} not found` });
      return;
    }
    await reply.send({ success: true, data: master });
  };

  createMaster = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const input = await this.parse(createMasterSchema, request.body, reply);
    if (input === null) return;
    await this.send(reply, await this.service.createMaster(input), 201);
  };

  updateMaster = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;
    const patch = await this.parse(updateMasterSchema, request.body, reply);
    if (patch === null) return;
    await this.send(reply, await this.service.updateMaster(account, patch));
  };

  deleteMaster = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;
    await this.send(reply, await this.service.deleteMaster(account));
  };

  //--- Followers ---------------------------------------------------------

  listFollowers = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const query = await this.parse(listFollowersQuerySchema, request.query, reply);
    if (query === null) return;
    await reply.send({ success: true, data: await this.service.listFollowers(query.masterAccount) });
  };

  getFollower = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;

    const follower = await this.service.getFollower(account);
    if (follower === null) {
      await reply.status(404).send({ success: false, error: `Follower ${account} not found` });
      return;
    }
    await reply.send({ success: true, data: follower });
  };

  createFollower = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const input = await this.parse(createFollowerSchema, request.body, reply);
    if (input === null) return;
    await this.send(reply, await this.service.createFollower(input), 201);
  };

  updateFollower = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;
    const patch = await this.parse(updateFollowerSchema, request.body, reply);
    if (patch === null) return;
    await this.send(reply, await this.service.updateFollower(account, patch));
  };

  deleteFollower = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const account = await this.account(request, reply);
    if (account === null) return;
    await this.send(reply, await this.service.deleteFollower(account));
  };

  //--- Helpers -----------------------------------------------------------

  // Parsed value, or null after replying 400
  private async parse<T>(schema: ZodType<T>, value: unknown, reply: FastifyReply): Promise<T | null> {
    const result = schema.safeParse(value ?? {});
    if (result.success) return result.data;

    await reply.status(400).send({
      success: false,
      error: "Invalid request",
      issues: result.error.issues,
    });
    return null;
  }

  private async account(request: FastifyRequest, reply: FastifyReply): Promise<string | null> {
    const params = await this.parse(accountParamsSchema, request.params, reply);
    return params?.account ?? null;
  }

  private async send<T>(reply: FastifyReply, result: AdminResult<T>, okStatus = 200): Promise<void> {
    if (result.status === "ok") {
      await reply.status(okStatus).send({ success: true, data: result.data });
      return;
    }
    await reply.status(STATUS_CODES[result.status]).send({ success: false, error: result.error });
  }
}
