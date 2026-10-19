import type { z } from "zod";
import type {
  createFollowerSchema,
  createMasterSchema,
  updateFollowerSchema,
  updateMasterSchema,
} from "./accounts.schema.js";

export interface MasterAccount {
  accountNumber: string;
  name: string;
  note: string;
  enabled: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface FollowerAccount {
  accountNumber: string;
  // The master this account copies
  masterAccount: string;
  name: string;
  note: string;
  createdAt: string;
  updatedAt: string;
}

export type CreateMasterInput = z.infer<typeof createMasterSchema>;
export type UpdateMasterInput = z.infer<typeof updateMasterSchema>;
export type CreateFollowerInput = z.infer<typeof createFollowerSchema>;
export type UpdateFollowerInput = z.infer<typeof updateFollowerSchema>;

// Storage for masters, followers and who follows whom. Async so a Redis
// implementation can replace the file one without changing callers.
export interface AccountRepository {
  listMasters(): Promise<MasterAccount[]>;
  getMaster(account: string): Promise<MasterAccount | null>;
  saveMaster(master: MasterAccount): Promise<void>;
  deleteMaster(account: string): Promise<void>;

  listFollowers(masterAccount?: string): Promise<FollowerAccount[]>;
  getFollower(account: string): Promise<FollowerAccount | null>;
  // Also moves the follower between masters' follower lists when masterAccount changes
  saveFollower(follower: FollowerAccount): Promise<void>;
  deleteFollower(account: string): Promise<void>;
}
