import { z } from "zod";
import { idStringSchema } from "../../lib/schemas.js";

export const followerPositionSchema = z
  .object({
    ticket: idStringSchema,
    symbol: z.string().trim().min(1),
    type: z.enum(["BUY", "SELL"]),
    volume: z.number().positive(),
    openPrice: z.number().positive(),
    currentPrice: z.number().nonnegative(),
    stopLoss: z.number().nonnegative(),
    takeProfit: z.number().nonnegative(),
    profit: z.number(),
    // Master ticket this position was copied from. null = not a copied trade.
    masterTicket: idStringSchema.nullable(),
    openTime: z.string().datetime({ offset: true }),
  })
  .strict();

// Lot size is set in the follower EA's MT5 inputs and reported on every sync
export const lotSettingsSchema = z
  .object({
    lotMode: z.enum(["SAME_AS_MASTER", "FIXED", "MULTIPLIER", "STEP_LOT"]),
    fixedLot: z.number().positive(),
    lotMultiplier: z.number().positive(),
    maxLot: z.number().positive(),
    stepStartMultiplier: z.number().positive(),
    stepMultiplier: z.number(),
    stepMinMultiplier: z.number().positive(),
    stepMaxMultiplier: z.number().positive(),
  })
  .strict();

export const followerSyncSchema = z
  .object({
    accountNumber: idStringSchema,
    broker: z.string().trim().min(1),
    server: z.string().trim().min(1),
    name: z.string().trim(),
    currency: z.string().trim().min(1),
    balance: z.number(),
    equity: z.number(),
    positions: z.array(followerPositionSchema),
    // Missing from EAs older than the lot-size inputs
    lotSettings: lotSettingsSchema.nullable().optional(),
    // Long polling: the master version the EA already has, and how long the
    // API may hold the request waiting for a change. Older EAs send neither.
    knownMasterVersion: z.number().int().nonnegative().optional(),
    waitMs: z.number().int().min(0).max(5000).optional(),
    // Settings version the EA is currently running with (0 = none yet).
    appliedSettingsVersion: z.number().int().nonnegative(),
    // Set when the EA stopped copying by itself (e.g. daily loss limit hit).
    autoStopReason: z.string().trim().min(1).nullable(),
    lastError: z.string().trim().min(1).nullable(),
    timestamp: z.string().datetime({ offset: true }),
  })
  .strict();

export const commandAckParamsSchema = z.object({ id: z.string().min(1) });

export const commandAckSchema = z
  .object({
    accountNumber: idStringSchema,
    status: z.enum(["done", "failed"]),
    error: z.string().trim().min(1).nullable(),
  })
  .strict();
