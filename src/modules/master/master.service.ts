import type { ChangeFeed } from "../../lib/change-feed.js";
import type { MasterStateStore } from "../../stores/master-state.store.js";
import type { AccountRepository } from "../accounts/accounts.types.js";
import type { MasterState } from "./master.types.js";

export type UpdateStateResult =
  | { status: "ok"; state: MasterState }
  | { status: "not_registered" }
  | { status: "disabled" };

export class MasterService {
  constructor(
    private readonly store: MasterStateStore,
    private readonly accountRepository: AccountRepository,
    private readonly changeFeed: ChangeFeed,
  ) {}

  // Only masters added through the admin API are copied
  async updateState(state: MasterState): Promise<UpdateStateResult> {
    const account = String(state.accountNumber);
    const master = await this.accountRepository.getMaster(account);

    if (master === null) return { status: "not_registered" };
    if (!master.enabled) return { status: "disabled" };

    // Wake this master's waiting followers only for real changes, not heartbeats
    if (this.store.set(account, state)) {
      this.changeFeed.notifyMaster(account);
    }

    return { status: "ok", state };
  }
}
