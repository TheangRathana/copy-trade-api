import { z } from "zod";
import { idStringSchema } from "../../lib/schemas.js";

export const loginSchema = z
  .object({
    accountNumber: idStringSchema,
    pairingCode: z.string().trim().regex(/^\d{6}$/, "Must be 6 digits"),
  })
  .strict();
