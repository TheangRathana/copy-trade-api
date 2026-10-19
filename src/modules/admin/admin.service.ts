import { config } from "../../config.js";
import type { ChangeFeed } from "../../lib/change-feed.js";
import type { FollowerStore } from "../../stores/follower.store.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { SessionStore } from "../../stores/session.store.js";
import type { SettingsStore } from "../../stores/settings.store.js";
import type {
  AccountRepository,
  CreateFollowerInput,
  CreateMasterInput,
  FollowerAccount,
  MasterAccount,
  UpdateFollowerInput,
  UpdateMasterInput,
} from "../accounts/accounts.types.js";

export interface AdminStores {
  accountRepository: AccountRepository;
  masterStore: MasterStateStore;
  followerStore: FollowerStore;
  settingsStore: SettingsStore;
  sessionStore: SessionStore;
  changeFeed: ChangeFeed;
}

// What a write did: the saved record, or why it was refused
export type AdminResult<T> =
  | { status: "ok"; data: T }
  | { status: "not_found"; error: string }
  | { status: "conflict"; error: string }
  | { status: "invalid"; error: string };

const notFound = (what: string, account: string) =>
  ({ status: "not_found", error: `${what} ${account} not found` }) as const;

export class AdminService {
  constructor(private readonly stores: AdminStores) {}

  //--- Masters -----------------------------------------------------------

  async listMasters() {
    const masters = await this.stores.accountRepository.listMasters();
    return Promise.all(masters.map((master) => this.masterView(master)));
  }

  async getMaster(account: string) {
    const master = await this.stores.accountRepository.getMaster(account);
    if (master === null) return null;

    const followers = await this.stores.accountRepository.listFollowers(account);
    return {
      ...(await this.masterView(master)),
      followers: followers.map((follower) => this.followerView(follower)),
    };
  }

  async createMaster(input: CreateMasterInput): Promise<AdminResult<MasterAccount>> {
    const { accountRepository } = this.stores;
    const account = input.accountNumber;

    if (await accountRepository.getMaster(account)) {
      return { status: "conflict", error: `Master ${account} already exists` };
    }
    if (await accountRepository.getFollower(account)) {
      return { status: "conflict", error: `Account ${account} is a follower; an account can't be both` };
    }

    const now = new Date().toISOString();
    const master: MasterAccount = { ...input, accountNumber: account, createdAt: now, updatedAt: now };
    await accountRepository.saveMaster(master);
    return { status: "ok", data: master };
  }

  async updateMaster(account: string, patch: UpdateMasterInput): Promise<AdminResult<MasterAccount>> {
    const current = await this.stores.accountRepository.getMaster(account);
    if (current === null) return notFound("Master", account);

    const master: MasterAccount = { ...current, ...patch, updatedAt: new Date().toISOString() };
    await this.stores.accountRepository.saveMaster(master);

    // Turning a master on or off changes what its followers receive
    if (patch.enabled !== undefined && patch.enabled !== current.enabled) {
      this.stores.changeFeed.notifyMaster(account);
    }

    return { status: "ok", data: master };
  }

  async deleteMaster(account: string): Promise<AdminResult<{ accountNumber: string }>> {
    const { accountRepository } = this.stores;
    if ((await accountRepository.getMaster(account)) === null) return notFound("Master", account);

    const followers = await accountRepository.listFollowers(account);
    if (followers.length > 0) {
      return {
        status: "conflict",
        error: `Master ${account} has ${followers.length} follower(s). Move them to another master or delete them first.`,
      };
    }

    await accountRepository.deleteMaster(account);
    this.stores.masterStore.delete(account);
    return { status: "ok", data: { accountNumber: account } };
  }

  //--- Followers ---------------------------------------------------------

  async listFollowers(masterAccount?: string) {
    const followers = await this.stores.accountRepository.listFollowers(masterAccount);
    return followers.map((follower) => this.followerView(follower));
  }

  async getFollower(account: string) {
    const follower = await this.stores.accountRepository.getFollower(account);
    if (follower === null) return null;

    const record = this.stores.settingsStore.get(account);
    return {
      ...this.followerView(follower),
      copy: record ? { enabled: record.copyEnabled, stopReason: record.stopReason } : null,
      settings: record?.settings ?? null,
      lotSettings: this.stores.followerStore.get(account)?.lotSettings ?? null,
    };
  }

  async createFollower(input: CreateFollowerInput): Promise<AdminResult<FollowerAccount>> {
    const { accountRepository } = this.stores;
    const account = input.accountNumber;

    if (await accountRepository.getFollower(account)) {
      return { status: "conflict", error: `Follower ${account} already exists` };
    }
    if (await accountRepository.getMaster(account)) {
      return { status: "conflict", error: `Account ${account} is a master; an account can't be both` };
    }
    if ((await accountRepository.getMaster(input.masterAccount)) === null) {
      return { status: "invalid", error: `Master ${input.masterAccount} does not exist` };
    }

    const now = new Date().toISOString();
    const follower: FollowerAccount = { ...input, accountNumber: account, createdAt: now, updatedAt: now };
    await accountRepository.saveFollower(follower);
    this.stores.changeFeed.notifyAccount(account);
    return { status: "ok", data: follower };
  }

  async updateFollower(account: string, patch: UpdateFollowerInput): Promise<AdminResult<FollowerAccount>> {
    const { accountRepository } = this.stores;
    const current = await accountRepository.getFollower(account);
    if (current === null) return notFound("Follower", account);

    if (patch.masterAccount !== undefined && (await accountRepository.getMaster(patch.masterAccount)) === null) {
      return { status: "invalid", error: `Master ${patch.masterAccount} does not exist` };
    }

    const follower: FollowerAccount = { ...current, ...patch, updatedAt: new Date().toISOString() };
    await accountRepository.saveFollower(follower);

    // A new master: the EA should pick it up now, not after its wait ends
    if (follower.masterAccount !== current.masterAccount) {
      this.stores.changeFeed.notifyAccount(account);
    }

    return { status: "ok", data: follower };
  }

  async deleteFollower(account: string): Promise<AdminResult<{ accountNumber: string }>> {
    const { accountRepository, settingsStore, sessionStore, changeFeed } = this.stores;
    if ((await accountRepository.getFollower(account)) === null) return notFound("Follower", account);

    await accountRepository.deleteFollower(account);
    settingsStore.delete(account);
    // Its dashboard logins end with it
    sessionStore.revokeAll(account);
    changeFeed.notifyAccount(account);
    return { status: "ok", data: { accountNumber: account } };
  }

  //--- Views -------------------------------------------------------------

  private async masterView(master: MasterAccount) {
    const { masterStore, accountRepository } = this.stores;
    const receivedAt = masterStore.getReceivedAt(master.accountNumber);
    const followers = await accountRepository.listFollowers(master.accountNumber);

    return {
      ...master,
      online: receivedAt !== null && Date.now() - receivedAt <= config.masterOnlineMs,
      lastSeenAt: receivedAt === null ? null : new Date(receivedAt).toISOString(),
      openPositions: masterStore.get(master.accountNumber)?.positions.length ?? 0,
      followerCount: followers.length,
    };
  }

  private followerView(follower: FollowerAccount) {
    const status = this.stores.followerStore.get(follower.accountNumber);
    return {
      ...follower,
      online:
        status !== null &&
        Date.now() - Date.parse(status.lastSeenAt) <= config.followerOnlineMs,
      lastSeenAt: status?.lastSeenAt ?? null,
      balance: status?.balance ?? null,
      equity: status?.equity ?? null,
      openPositions: status?.positions.length ?? 0,
    };
  }
}
