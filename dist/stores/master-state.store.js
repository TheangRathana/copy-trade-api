export class MasterStateStore {
    latestState = null;
    set(state) {
        this.latestState = state;
        return state;
    }
    get() {
        return this.latestState;
    }
}
//# sourceMappingURL=master-state.store.js.map