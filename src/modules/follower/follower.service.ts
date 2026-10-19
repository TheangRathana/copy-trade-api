import { config } from "../../config.js";
import type { ChangeFeed } from "../../lib/change-feed.js";
import type { Command, CommandStore } from "../../stores/command.store.js";
import type { FollowerStore } from "../../stores/follower.store.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { PairingStore } from "../../stores/pairing.store.js";
import type { SettingsStore } from "../../stores/settings.store.js";
import type { AccountRepository } from "../accounts/accounts.types.js";
import type { CommandAck, FollowerSync } from "./follower.types.js";

export interface FollowerStores {
  masterStore: MasterStateStore;
  followerStore: FollowerStore;
  settingsStore: SettingsStore;
  commandStore: CommandStore;
  pairingStore: PairingStore;
  accountRepository: AccountRepository;
  changeFeed: ChangeFeed;
}

export class FollowerService {
  constructor(private readonly stores: FollowerStores) {}

  // One round trip per EA cycle: report status in, get everything it needs back.
  //
  // Long polling: when the EA already has the latest master state, settings
  // and no pending commands, the request is held for up to report.waitMs and
  // answered the moment something changes. This gets a master trade to the
  // follower within milliseconds, without the EA polling fast.
  async sync(report: FollowerSync) {
    const { followerStore, settingsStore } = this.stores;
    const account = report.accountNumber;

    followerStore.set(report);

    const record = settingsStore.getOrCreate(account);

    if (report.autoStopReason !== null && record.copyEnabled) {
      settingsStore.update(account, {
        copyEnabled: false,
        stopReason: report.autoStopReason,
      });
    }

    const master = await this.assignedMaster(account);

    if (report.waitMs && this.isUpToDate(report, master)) {
      await this.stores.changeFeed.waitFor(account, master, report.waitMs);
      // The assignment may have changed while waiting
      return this.syncResponse(account, await this.assignedMaster(account));
    }

    return this.syncResponse(account, master);
  }

  // The master this follower copies, or null when it isn't registered, has no
  // master, or its master is disabled. With null the EA copies nothing.
  private async assignedMaster(account: string): Promise<string | null> {
    const { accountRepository } = this.stores;
    const follower = await accountRepository.getFollower(account);
    if (follower === null) return null;

    const master = await accountRepository.getMaster(follower.masterAccount);
    return master !== null && master.enabled ? master.accountNumber : null;
  }

  private isUpToDate(report: FollowerSync, master: string | null): boolean {
    const { masterStore, settingsStore, commandStore } = this.stores;
    const account = report.accountNumber;
    const masterVersion = master === null ? 0 : masterStore.getVersion(master);

    return (
      report.knownMasterVersion === masterVersion &&
      report.appliedSettingsVersion === settingsStore.getOrCreate(account).version &&
      commandStore.listPending(account).length === 0
    );
  }

  private syncResponse(account: string, master: string | null) {
    const { masterStore, settingsStore, commandStore, pairingStore } = this.stores;
    const record = settingsStore.getOrCreate(account);
    const receivedAt = master === null ? null : masterStore.getReceivedAt(master);

    return {
      master: {
        // null = not assigned to an enabled master
        account: master,
        online:
          receivedAt !== null && Date.now() - receivedAt <= config.masterOnlineMs,
        version: master === null ? 0 : masterStore.getVersion(master),
        state: master === null ? null : masterStore.get(master),
      },
      copyEnabled: record.copyEnabled,
      stopReason: record.stopReason,
      settingsVersion: record.version,
      settings: record.settings,
      commands: commandStore.listPending(account).map((command) => ({
        id: command.id,
        type: command.type,
        ticket: command.ticket,
      })),
      pairing: pairingStore.getOrCreate(account),
    };
  }

  ackCommand(id: string, ack: CommandAck): Command | null {
    const command = this.stores.commandStore.get(id);

    if (command === null || command.account !== ack.accountNumber) {
      return null;
    }

    return this.stores.commandStore.complete(id, ack.status, ack.error);
  }
}
