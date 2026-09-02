import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { MasterState } from "./master.types.js";

export class MasterService {
  constructor(private readonly store: MasterStateStore) {}

  updateState(state: MasterState): MasterState {
    return this.store.set(state);
  }

  getLatestState(): MasterState | null {
    return this.store.get();
  }
}
