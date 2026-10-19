import type { MasterState } from "../modules/master/master.types.js";

interface MasterLiveState {
  state: MasterState;
  // When the master EA last posted, as epoch ms
  receivedAt: number;
  // Goes up when the positions change (not on heartbeats), so a follower can
  // tell whether it already has the latest state
  version: number;
  positionsSnapshot: string;
}

// The latest state each master EA posted, keyed by master account number.
export class MasterStateStore {
  private readonly masters = new Map<string, MasterLiveState>();

  // Returns true when the positions changed
  set(account: string, state: MasterState): boolean {
    const snapshot = JSON.stringify(state.positions);
    const current = this.masters.get(account);
    const changed = current === undefined || current.positionsSnapshot !== snapshot;

    this.masters.set(account, {
      state,
      receivedAt: Date.now(),
      version: changed ? (current?.version ?? 0) + 1 : current.version,
      positionsSnapshot: snapshot,
    });
    return changed;
  }

  get(account: string): MasterState | null {
    return this.masters.get(account)?.state ?? null;
  }

  getVersion(account: string): number {
    return this.masters.get(account)?.version ?? 0;
  }

  getReceivedAt(account: string): number | null {
    return this.masters.get(account)?.receivedAt ?? null;
  }

  delete(account: string): void {
    this.masters.delete(account);
  }
}
