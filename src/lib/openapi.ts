import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";

// JSON Schema for the Swagger docs, built from the same zod schemas the
// controllers validate with, so the docs can't drift from the code.
export function jsonSchema(schema: ZodType): Record<string, unknown> {
  const json = z.toJSONSchema(schema, {
    io: "input",
    target: "draft-7",
    unrepresentable: "any",
  }) as Record<string, unknown>;
  delete json.$schema;
  return json;
}

export const TAGS = {
  health: "Health",
  ea: "EA (MT5)",
  auth: "Auth",
  dashboard: "Dashboard",
  admin: "Admin",
} as const;

export const ADMIN_SECURITY = [{ adminKey: [] }];
export const EA_SECURITY = [{ eaKey: [] }];
export const SESSION_SECURITY = [{ sessionToken: [] }];

// Swagger UI at /docs, the OpenAPI spec at /docs/json. Register before the routes.
export function registerDocs(app: FastifyInstance): void {
  // Requests are validated by zod in the controllers. Route schemas are only
  // for the docs, so Fastify must not validate or reshape anything with them.
  app.setValidatorCompiler(() => () => true);

  void app.register(swagger, {
    openapi: {
      info: {
        title: "Copy Trade API",
        version: "1.0.0",
        description:
          "Copies trades from master MT5 accounts to follower accounts.\n\n" +
          "- **EA** endpoints: for the MT5 EAs. They send the server's EA_API_KEY in the " +
          "`X-EA-Key` header (or run on the same machine as the API).\n" +
          "- **Auth / Dashboard**: the web dashboard. Log in with the account number and the " +
          "6-digit code from the follower EA's chart, then send the token as a Bearer token.\n" +
          "- **Admin**: manage masters and followers with the ADMIN_API_KEY as a Bearer token.\n\n" +
          "Every response is `{ success: true, data }` or `{ success: false, error, issues? }`.",
      },
      tags: [
        { name: TAGS.health },
        { name: TAGS.ea, description: "Called by the MT5 EAs with the X-EA-Key header" },
        { name: TAGS.auth, description: "Dashboard login with the EA's pairing code" },
        { name: TAGS.dashboard, description: "The logged-in follower account" },
        { name: TAGS.admin, description: "Masters, followers and who follows whom" },
      ],
      components: {
        securitySchemes: {
          adminKey: {
            type: "http",
            scheme: "bearer",
            description: "The server's ADMIN_API_KEY",
          },
          eaKey: {
            type: "apiKey",
            in: "header",
            name: "X-EA-Key",
            description: "The server's EA_API_KEY",
          },
          sessionToken: {
            type: "http",
            scheme: "bearer",
            description: "Token from POST /api/auth/login",
          },
        },
      },
    },
  });

  void app.register(swaggerUi, { routePrefix: "/docs" });
}
