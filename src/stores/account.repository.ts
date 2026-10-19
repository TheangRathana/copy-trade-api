import path from "node:path";
import { readJsonFile, writeJsonFile } from "../lib/json-file.js";
import type {
  AccountRepository,
  FollowerAccount,
  MasterAccount,
} from "../modules/accounts/accounts.types.js";

interface AccountsFile {
  masters: Record<string, MasterAccount>;
  followers: Record<string, FollowerAccount>;
}

// Masters and followers kept in data/<PORT>/accounts.json. Replaced by a Redis
// implementation of AccountRepository once Redis is connected.
export class FileAccountRepository implements AccountRepository {
  private readonly filePath: string;
  private readonly data: AccountsFile;

  constructor(dataDir: string) {
    this.filePath = path.join(dataDir, "accounts.json");
    this.data = readJsonFile<AccountsFile>(this.filePath, {
      masters: {},
      followers: {},
    });
  }

  async listMasters(): Promise<MasterAccount[]> {
    return Object.values(this.data.masters);
  }

  async getMaster(account: string): Promise<MasterAccount | null> {
    return this.data.masters[account] ?? null;
  }

  async saveMaster(master: MasterAccount): Promise<void> {
    this.data.masters[master.accountNumber] = master;
    this.persist();
  }

  async deleteMaster(account: string): Promise<void> {
    delete this.data.masters[account];
    this.persist();
  }

  async listFollowers(masterAccount?: string): Promise<FollowerAccount[]> {
    const followers = Object.values(this.data.followers);
    return masterAccount === undefined
      ? followers
      : followers.filter((follower) => follower.masterAccount === masterAccount);
  }

  async getFollower(account: string): Promise<FollowerAccount | null> {
    return this.data.followers[account] ?? null;
  }

  async saveFollower(follower: FollowerAccount): Promise<void> {
    this.data.followers[follower.accountNumber] = follower;
    this.persist();
  }

  async deleteFollower(account: string): Promise<void> {
    delete this.data.followers[account];
    this.persist();
  }

  private persist(): void {
    writeJsonFile(this.filePath, this.data);
  }
}
