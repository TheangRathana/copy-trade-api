import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { MasterState } from "./master.types.js";
export declare class MasterService {
    private readonly store;
    constructor(store: MasterStateStore);
    updateState(state: MasterState): MasterState;
    getLatestState(): MasterState | null;
}
//# sourceMappingURL=master.service.d.ts.map