import { z } from "zod";

export const lotModeSchema = z.enum([
  "SAME_AS_MASTER",
  "FIXED",
  "MULTIPLIER",
  "STEP_LOT",
]);

const symbolMappingSchema = z
  .object({
    master: z.string().trim().min(1),
    follower: z.string().trim().min(1),
  })
  .strict();

const copySettingsShape = z
  .object({
    copyBuy: z.boolean(),
    copySell: z.boolean(),
    copyStopLoss: z.boolean(),
    copyTakeProfit: z.boolean(),
    copyModify: z.boolean(),
    copyClosedPositions: z.boolean(),

    lotMode: lotModeSchema,
    fixedLot: z.number().positive(),
    lotMultiplier: z.number().positive(),
    maxLot: z.number().positive(),
    stepStartMultiplier: z.number().positive(),
    stepMultiplier: z.number().positive(),
    stepMinMultiplier: z.number().positive(),
    stepMaxMultiplier: z.number().positive(),

    autoDetectSymbol: z.boolean(),
    symbolMappings: z.array(symbolMappingSchema).max(200),

    // 0 = unlimited / off.
    maxOpenPositions: z.number().int().nonnegative(),
    maxDailyLossPercent: z.number().min(0).max(100),
    closeAllOnDailyLoss: z.boolean(),
  })
  .strict();

export const copySettingsSchema = copySettingsShape.superRefine(
  (settings, ctx) => {
    if (settings.lotMode === "FIXED" && settings.fixedLot > settings.maxLot) {
      ctx.addIssue({
        code: "custom",
        path: ["fixedLot"],
        message: "fixedLot must not be greater than maxLot",
      });
    }

    if (settings.stepMinMultiplier > settings.stepMaxMultiplier) {
      ctx.addIssue({
        code: "custom",
        path: ["stepMinMultiplier"],
        message: "stepMinMultiplier must not be greater than stepMaxMultiplier",
      });
    }
  },
);

export const copySettingsPatchSchema = copySettingsShape
  .partial()
  .refine((patch) => Object.keys(patch).length > 0, {
    message: "No settings to update",
  });
