import type { Redis } from "ioredis";
import type {
  AccountRepository,
  FollowerAccount,
  MasterAccount,
} from "../modules/accounts/accounts.types.js";

// Masters, followers and who follows whom, in Redis. Keys (all prefixed "ct:"
// by the client):
//
//   masters                    SET   all master account numbers
//   master:{acct}              HASH  accountNumber, name, note, enabled (1/0), createdAt, updatedAt
//   master:{acct}:followers    SET   accounts following this master
//   followers                  SET   all follower account numbers
//   follower:{acct}            HASH  accountNumber, masterAccount, name, note, createdAt, updatedAt
const keys = {
  masters: "masters",
  master: (account: string) => `master:${account}`,
  masterFollowers: (account: string) => `master:${account}:followers`,
  followers: "followers",
  follower: (account: string) => `follower:${account}`,
};

const toMaster = (hash: Record<string, string>): MasterAccount | null =>
  hash.accountNumber === undefined
    ? null
    : {
        accountNumber: hash.accountNumber,
        name: hash.name ?? "",
        note: hash.note ?? "",
        enabled: hash.enabled === "1",
        createdAt: hash.createdAt ?? "",
        updatedAt: hash.updatedAt ?? "",
      };

const toFollower = (hash: Record<string, string>): FollowerAccount | null =>
  hash.accountNumber === undefined
    ? null
    : {
        accountNumber: hash.accountNumber,
        masterAccount: hash.masterAccount ?? "",
        name: hash.name ?? "",
        note: hash.note ?? "",
        createdAt: hash.createdAt ?? "",
        updatedAt: hash.updatedAt ?? "",
      };

const byAccount = <T extends { accountNumber: string }>(a: T, b: T) =>
  a.accountNumber.localeCompare(b.accountNumber, undefined, { numeric: true });

export class RedisAccountRepository implements AccountRepository {
  constructor(private readonly redis: Redis) {}

  async listMasters(): Promise<MasterAccount[]> {
    const accounts = await this.redis.smembers(keys.masters);
    return (await this.readHashes(accounts.map(keys.master)))
      .map(toMaster)
      .filter((master): master is MasterAccount => master !== null)
      .sort(byAccount);
  }

  async getMaster(account: string): Promise<MasterAccount | null> {
    return toMaster(await this.redis.hgetall(keys.master(account)));
  }

  async saveMaster(master: MasterAccount): Promise<void> {
    await this.redis
      .multi()
      .hset(keys.master(master.accountNumber), {
        accountNumber: master.accountNumber,
        name: master.name,
        note: master.note,
        enabled: master.enabled ? "1" : "0",
        createdAt: master.createdAt,
        updatedAt: master.updatedAt,
      })
      .sadd(keys.masters, master.accountNumber)
      .exec();
  }

  async deleteMaster(account: string): Promise<void> {
    await this.redis
      .multi()
      .del(keys.master(account), keys.masterFollowers(account))
      .srem(keys.masters, account)
      .exec();
  }

  async listFollowers(masterAccount?: string): Promise<FollowerAccount[]> {
    const accounts = await this.redis.smembers(
      masterAccount === undefined ? keys.followers : keys.masterFollowers(masterAccount),
    );
    return (await this.readHashes(accounts.map(keys.follower)))
      .map(toFollower)
      .filter((follower): follower is FollowerAccount => follower !== null)
      .sort(byAccount);
  }

  async getFollower(account: string): Promise<FollowerAccount | null> {
    return toFollower(await this.redis.hgetall(keys.follower(account)));
  }

  async saveFollower(follower: FollowerAccount): Promise<void> {
    const account = follower.accountNumber;
    const previousMaster = await this.redis.hget(keys.follower(account), "masterAccount");

    const transaction = this.redis
      .multi()
      .hset(keys.follower(account), {
        accountNumber: account,
        masterAccount: follower.masterAccount,
        name: follower.name,
        note: follower.note,
        createdAt: follower.createdAt,
        updatedAt: follower.updatedAt,
      })
      .sadd(keys.followers, account)
      .sadd(keys.masterFollowers(follower.masterAccount), account);

    // Moved to another master: leave the old master's list
    if (previousMaster && previousMaster !== follower.masterAccount) {
      transaction.srem(keys.masterFollowers(previousMaster), account);
    }

    await transaction.exec();
  }

  async deleteFollower(account: string): Promise<void> {
    const masterAccount = await this.redis.hget(keys.follower(account), "masterAccount");
    const transaction = this.redis
      .multi()
      .del(keys.follower(account))
      .srem(keys.followers, account);

    if (masterAccount) {
      transaction.srem(keys.masterFollowers(masterAccount), account);
    }

    await transaction.exec();
  }

  // HGETALL for many keys in one round trip
  private async readHashes(hashKeys: string[]): Promise<Record<string, string>[]> {
    if (hashKeys.length === 0) return [];

    const pipeline = this.redis.pipeline();
    for (const key of hashKeys) pipeline.hgetall(key);
    const results = (await pipeline.exec()) ?? [];

    return results.map(([error, hash]) => {
      if (error) throw error;
      return hash as Record<string, string>;
    });
  }
}
