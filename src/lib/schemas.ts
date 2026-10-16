import { z } from "zod";

export const identifierSchema = z.union([
  z.string().trim().min(1),
  z.number().int().nonnegative(),
]);

// Account numbers and tickets are compared as strings everywhere.
export const idStringSchema = identifierSchema.transform(String);
