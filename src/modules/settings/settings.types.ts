import type { z } from "zod";
import type {
  copySettingsPatchSchema,
  copySettingsSchema,
} from "./settings.schema.js";

export type CopySettings = z.infer<typeof copySettingsSchema>;
export type CopySettingsPatch = z.infer<typeof copySettingsPatchSchema>;

export interface FollowerSettingsRecord {
  copyEnabled: boolean;
  // Why copying was stopped (user stop, daily loss limit, ...). null while copying.
  stopReason: string | null;
  settings: CopySettings;
  // Bumped on every change so the UI can tell when the EA has applied it.
  version: number;
  updatedAt: string;
}

// Same defaults as the EA inputs.
export const DEFAULT_COPY_SETTINGS: CopySettings = {
  copyBuy: true,
  copySell: true,
  copyStopLoss: true,
  copyTakeProfit: true,
  copyModify: true,
  copyClosedPositions: true,
  lotMode: "SAME_AS_MASTER",
  fixedLot: 0.01,
  lotMultiplier: 1,
  maxLot: 10,
  stepStartMultiplier: 1,
  stepMultiplier: 0.5,
  stepMinMultiplier: 0.1,
  stepMaxMultiplier: 10,
  autoDetectSymbol: true,
  symbolMappings: [],
  maxOpenPositions: 0,
  maxDailyLossPercent: 0,
  closeAllOnDailyLoss: false,
};
