export class MasterService {
    store;
    constructor(store) {
        this.store = store;
    }
    updateState(state) {
        return this.store.set(state);
    }
    getLatestState() {
        return this.store.get();
    }
}
//# sourceMappingURL=master.service.js.map