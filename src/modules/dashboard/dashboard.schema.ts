import { z } from "zod";
import { idStringSchema } from "../../lib/schemas.js";

export const stopCopySchema = z
  .object({
    // Also close every copied position on this account.
    closeAll: z.boolean().default(false),
  })
  .strict();

export const createCommandSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("CLOSE_POSITION"), ticket: idStringSchema }).strict(),
  z.object({ type: z.literal("CLOSE_ALL") }).strict(),
]);

export const commandParamsSchema = z.object({ id: z.string().min(1) });
