import type { FastifyReply, FastifyRequest } from "fastify";
import { loginSchema } from "./auth.schema.js";
import type { AuthService } from "./auth.service.js";

export class AuthController {
  constructor(private readonly service: AuthService) {}

  login = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const result = loginSchema.safeParse(request.body);

    if (!result.success) {
      await reply.status(400).send({
        success: false,
        error: "Invalid login",
        issues: result.error.issues,
      });
      return;
    }

    const login = this.service.login(
      result.data.accountNumber,
      result.data.pairingCode,
    );

    if (login.status === "locked") {
      await reply
        .status(429)
        .header("retry-after", String(login.retryAfterSeconds))
        .send({
          success: false,
          error: "Too many failed attempts",
          retryAfterSeconds: login.retryAfterSeconds,
        });
      return;
    }

    if (login.status === "invalid") {
      await reply.status(401).send({
        success: false,
        error: "Invalid account number or pairing code",
      });
      return;
    }

    await reply.send({
      success: true,
      data: {
        accountNumber: result.data.accountNumber,
        token: login.token,
        expiresAt: login.expiresAt,
      },
    });
  };

  logout = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    this.service.logout(request.sessionToken);
    await reply.send({ success: true });
  };

  logoutAll = async (
    request: FastifyRequest,
    reply: FastifyReply,
  ): Promise<void> => {
    this.service.logoutAll(request.sessionAccount);
    await reply.send({ success: true });
  };
}
