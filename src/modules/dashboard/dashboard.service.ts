import type { z } from "zod";
import { config } from "../../config.js";
import type { ChangeFeed } from "../../lib/change-feed.js";
import type { Command, CommandStore } from "../../stores/command.store.js";
import type { FollowerStore } from "../../stores/follower.store.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { SettingsStore } from "../../stores/settings.store.js";
import type { AccountRepository } from "../accounts/accounts.types.js";
import { copySettingsSchema } from "../settings/settings.schema.js";
import type { CopySettingsPatch } from "../settings/settings.types.js";
import type { createCommandSchema } from "./dashboard.schema.js";

export interface DashboardStores {
  masterStore: MasterStateStore;
  followerStore: FollowerStore;
  settingsStore: SettingsStore;
  commandStore: CommandStore;
  accountRepository: AccountRepository;
  changeFeed: ChangeFeed;
}

type CreateCommandInput = z.infer<typeof createCommandSchema>;

export type CreateCommandResult =
  | { status: "ok"; command: Command }
  | { status: "offline" }
  | { status: "position_not_found" };

export class DashboardService {
  constructor(private readonly stores: DashboardStores) {}

  async getAccount(account: string) {
    const { masterStore, followerStore, settingsStore, accountRepository } = this.stores;
    const follower = followerStore.get(account);
    const record = settingsStore.getOrCreate(account);
    const assignment = await accountRepository.getFollower(account);
    const master = assignment ? await accountRepository.getMaster(assignment.masterAccount) : null;
    const masterReceivedAt = master ? masterStore.getReceivedAt(master.accountNumber) : null;
    const appliedSettingsVersion = follower?.appliedSettingsVersion ?? 0;

    return {
      accountNumber: account,
      online: this.isOnline(account),
      lastSeenAt: follower?.lastSeenAt ?? null,
      lastError: follower?.lastError ?? null,
      account:
        follower === null
          ? null
          : {
              broker: follower.broker,
              server: follower.server,
              name: follower.name,
              currency: follower.currency,
              balance: follower.balance,
              equity: follower.equity,
            },
      // The master this account copies; null when it has none yet
      master: {
        account: master?.accountNumber ?? null,
        name: master?.name ?? null,
        enabled: master?.enabled ?? false,
        online:
          masterReceivedAt !== null &&
          Date.now() - masterReceivedAt <= config.masterOnlineMs,
      },
      copy: {
        enabled: record.copyEnabled,
        stopReason: record.stopReason,
      },
      settings: record.settings,
      // Set in the EA's MT5 inputs; null until an EA that reports it syncs
      lotSettings: follower?.lotSettings ?? null,
      settingsVersion: record.version,
      appliedSettingsVersion,
      settingsApplied: appliedSettingsVersion >= record.version,
      positions: follower?.positions ?? [],
    };
  }

  async updateSettings(account: string, patch: CopySettingsPatch) {
    const record = this.stores.settingsStore.getOrCreate(account);
    const result = copySettingsSchema.safeParse({ ...record.settings, ...patch });

    if (!result.success) {
      return { success: false as const, issues: result.error.issues };
    }

    this.stores.settingsStore.update(account, { settings: result.data });
    this.stores.changeFeed.notifyAccount(account);
    return { success: true as const, data: await this.getAccount(account) };
  }

  async startCopy(account: string) {
    const record = this.stores.settingsStore.getOrCreate(account);

    if (!record.copyEnabled) {
      this.stores.settingsStore.update(account, {
        copyEnabled: true,
        stopReason: null,
      });
      this.stores.changeFeed.notifyAccount(account);
    }

    return await this.getAccount(account);
  }

  async stopCopy(account: string, closeAll: boolean) {
    const record = this.stores.settingsStore.getOrCreate(account);

    if (record.copyEnabled) {
      this.stores.settingsStore.update(account, {
        copyEnabled: false,
        stopReason: "Stopped by user",
      });
    }

    const command = closeAll
      ? this.stores.commandStore.create(account, "CLOSE_ALL", null)
      : null;

    this.stores.changeFeed.notifyAccount(account);
    return { ...(await this.getAccount(account)), command };
  }

  createCommand(account: string, input: CreateCommandInput): CreateCommandResult {
    // Queued commands expire quickly, so refuse them while the EA is offline.
    if (!this.isOnline(account)) {
      return { status: "offline" };
    }

    if (input.type === "CLOSE_POSITION") {
      const positions = this.stores.followerStore.get(account)?.positions ?? [];

      if (!positions.some((position) => position.ticket === input.ticket)) {
        return { status: "position_not_found" };
      }

      return this.queueCommand(account, "CLOSE_POSITION", input.ticket);
    }

    return this.queueCommand(account, "CLOSE_ALL", null);
  }

  // Wakes the follower's waiting sync so the command runs right away
  private queueCommand(
    account: string,
    type: Command["type"],
    ticket: string | null,
  ): CreateCommandResult {
    const command = this.stores.commandStore.create(account, type, ticket);
    this.stores.changeFeed.notifyAccount(account);
    return { status: "ok", command };
  }

  getCommand(account: string, id: string): Command | null {
    const command = this.stores.commandStore.get(id);
    return command !== null && command.account === account ? command : null;
  }

  listCommands(account: string): Command[] {
    return this.stores.commandStore.list(account);
  }

  private isOnline(account: string): boolean {
    const follower = this.stores.followerStore.get(account);
    return (
      follower !== null &&
      Date.now() - Date.parse(follower.lastSeenAt) <= config.followerOnlineMs
    );
  }
}
