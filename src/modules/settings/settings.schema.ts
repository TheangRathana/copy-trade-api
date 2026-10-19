import { z } from "zod";

// Settings changed from the web dashboard. Lot size is set in the follower
// EA's MT5 inputs instead and reported on each sync (follower.schema.ts).
export const copySettingsSchema = z
  .object({
    copyBuy: z.boolean(),
    copySell: z.boolean(),
    copyStopLoss: z.boolean(),
    copyTakeProfit: z.boolean(),
    copyModify: z.boolean(),
    copyClosedPositions: z.boolean(),

    // 0 = unlimited / off.
    maxOpenPositions: z.number().int().nonnegative(),
    maxDailyLossPercent: z.number().min(0).max(100),
    closeAllOnDailyLoss: z.boolean(),
  })
  .strict();

export const copySettingsPatchSchema = copySettingsSchema
  .partial()
  .refine((patch) => Object.keys(patch).length > 0, {
    message: "No settings to update",
  });
