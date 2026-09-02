import { z } from "zod";
const identifierSchema = z.union([
    z.string().trim().min(1),
    z.number().int().nonnegative(),
]);
export const masterPositionSchema = z
    .object({
    ticket: identifierSchema,
    symbol: z.string().trim().min(1),
    type: z.enum(["BUY", "SELL"]),
    volume: z.number().positive(),
    openPrice: z.number().positive(),
    stopLoss: z.number().nonnegative(),
    takeProfit: z.number().nonnegative(),
})
    .strict();
export const masterStateSchema = z
    .object({
    accountNumber: identifierSchema,
    broker: z.string().trim().min(1),
    server: z.string().trim().min(1),
    positions: z.array(masterPositionSchema),
    timestamp: z.string().datetime({ offset: true }),
})
    .strict();
//# sourceMappingURL=master.schema.js.map