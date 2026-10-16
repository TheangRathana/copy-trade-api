import type { z } from "zod";
import { config } from "../../config.js";
import type { Command, CommandStore } from "../../stores/command.store.js";
import type { FollowerStore } from "../../stores/follower.store.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { SettingsStore } from "../../stores/settings.store.js";
import { copySettingsSchema } from "../settings/settings.schema.js";
import type { CopySettingsPatch } from "../settings/settings.types.js";
import type { createCommandSchema } from "./dashboard.schema.js";

export interface DashboardStores {
  masterStore: MasterStateStore;
  followerStore: FollowerStore;
  settingsStore: SettingsStore;
  commandStore: CommandStore;
}

type CreateCommandInput = z.infer<typeof createCommandSchema>;

export type CreateCommandResult =
  | { status: "ok"; command: Command }
  | { status: "offline" }
  | { status: "position_not_found" };

export class DashboardService {
  constructor(private readonly stores: DashboardStores) {}

  getAccount(account: string) {
    const { masterStore, followerStore, settingsStore } = this.stores;
    const follower = followerStore.get(account);
    const record = settingsStore.getOrCreate(account);
    const masterReceivedAt = masterStore.getReceivedAt();
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
      master: {
        online:
          masterReceivedAt !== null &&
          Date.now() - masterReceivedAt <= config.masterOnlineMs,
      },
      copy: {
        enabled: record.copyEnabled,
        stopReason: record.stopReason,
      },
      settings: record.settings,
      settingsVersion: record.version,
      appliedSettingsVersion,
      settingsApplied: appliedSettingsVersion >= record.version,
      positions: follower?.positions ?? [],
    };
  }

  updateSettings(account: string, patch: CopySettingsPatch) {
    const record = this.stores.settingsStore.getOrCreate(account);
    const result = copySettingsSchema.safeParse({ ...record.settings, ...patch });

    if (!result.success) {
      return { success: false as const, issues: result.error.issues };
    }

    this.stores.settingsStore.update(account, { settings: result.data });
    return { success: true as const, data: this.getAccount(account) };
  }

  startCopy(account: string) {
    const record = this.stores.settingsStore.getOrCreate(account);

    if (!record.copyEnabled) {
      this.stores.settingsStore.update(account, {
        copyEnabled: true,
        stopReason: null,
      });
    }

    return this.getAccount(account);
  }

  stopCopy(account: string, closeAll: boolean) {
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

    return { ...this.getAccount(account), command };
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

      return {
        status: "ok",
        command: this.stores.commandStore.create(
          account,
          "CLOSE_POSITION",
          input.ticket,
        ),
      };
    }

    return {
      status: "ok",
      command: this.stores.commandStore.create(account, "CLOSE_ALL", null),
    };
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
