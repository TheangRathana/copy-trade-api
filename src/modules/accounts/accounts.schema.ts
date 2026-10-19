import { z } from "zod";
import { idStringSchema } from "../../lib/schemas.js";

const nameSchema = z.string().trim().min(1).max(60);
const noteSchema = z.string().trim().max(500);

const atLeastOne = <T extends Record<string, unknown>>(patch: T) =>
  Object.keys(patch).length > 0;

export const accountParamsSchema = z.object({ account: idStringSchema });

export const createMasterSchema = z
  .object({
    accountNumber: idStringSchema,
    name: nameSchema,
    note: noteSchema.default(""),
    // false = followers stop receiving this master's trades
    enabled: z.boolean().default(true),
  })
  .strict();

export const updateMasterSchema = z
  .object({
    name: nameSchema,
    note: noteSchema,
    enabled: z.boolean(),
  })
  .partial()
  .strict()
  .refine(atLeastOne, { message: "Nothing to update" });

export const createFollowerSchema = z
  .object({
    accountNumber: idStringSchema,
    // The master this account copies (one master per follower)
    masterAccount: idStringSchema,
    name: nameSchema,
    note: noteSchema.default(""),
  })
  .strict();

export const updateFollowerSchema = z
  .object({
    masterAccount: idStringSchema,
    name: nameSchema,
    note: noteSchema,
  })
  .partial()
  .strict()
  .refine(atLeastOne, { message: "Nothing to update" });

export const listFollowersQuerySchema = z
  .object({ masterAccount: idStringSchema.optional() })
  .strict();
