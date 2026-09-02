import type { MasterState } from "../modules/master/master.types.js";

export class MasterStateStore {
  private latestState: MasterState | null = null;

  set(state: MasterState): MasterState {
    this.latestState = state;
    return state;
  }

  get(): MasterState | null {
    return this.latestState;
  }
}
