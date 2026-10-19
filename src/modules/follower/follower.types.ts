import type { z } from "zod";
import type {
  commandAckSchema,
  followerPositionSchema,
  followerSyncSchema,
  lotSettingsSchema,
} from "./follower.schema.js";

export type FollowerPosition = z.infer<typeof followerPositionSchema>;
export type FollowerSync = z.infer<typeof followerSyncSchema>;
export type LotSettings = z.infer<typeof lotSettingsSchema>;
export type CommandAck = z.infer<typeof commandAckSchema>;

export interface FollowerStatus extends FollowerSync {
  lastSeenAt: string;
}
