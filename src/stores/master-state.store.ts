import type { MasterState } from "../modules/master/master.types.js";

export class MasterStateStore {
  private latestState: MasterState | null = null;
  private receivedAt: number | null = null;

  set(state: MasterState): MasterState {
    this.latestState = state;
    this.receivedAt = Date.now();
    return state;
  }

  get(): MasterState | null {
    return this.latestState;
  }

  // When the master EA last posted its state, as epoch ms.
  getReceivedAt(): number | null {
    return this.receivedAt;
  }
}
