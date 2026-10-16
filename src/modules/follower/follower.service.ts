import { config } from "../../config.js";
import type { Command, CommandStore } from "../../stores/command.store.js";
import type { FollowerStore } from "../../stores/follower.store.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { PairingStore } from "../../stores/pairing.store.js";
import type { SettingsStore } from "../../stores/settings.store.js";
import type { CommandAck, FollowerSync } from "./follower.types.js";

export interface FollowerStores {
  masterStore: MasterStateStore;
  followerStore: FollowerStore;
  settingsStore: SettingsStore;
  commandStore: CommandStore;
  pairingStore: PairingStore;
}

export class FollowerService {
  constructor(private readonly stores: FollowerStores) {}

  // One round trip per EA cycle: report status in, get everything it needs back.
  sync(report: FollowerSync) {
    const { masterStore, followerStore, settingsStore, commandStore, pairingStore } =
      this.stores;
    const account = report.accountNumber;

    followerStore.set(report);

    let record = settingsStore.getOrCreate(account);

    if (report.autoStopReason !== null && record.copyEnabled) {
      record = settingsStore.update(account, {
        copyEnabled: false,
        stopReason: report.autoStopReason,
      });
    }

    const receivedAt = masterStore.getReceivedAt();

    return {
      master: {
        online:
          receivedAt !== null && Date.now() - receivedAt <= config.masterOnlineMs,
        state: masterStore.get(),
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
