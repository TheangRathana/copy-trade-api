import type { FollowerStore } from "../../stores/follower.store.js";
import type { PairingStore } from "../../stores/pairing.store.js";
import type { SessionStore } from "../../stores/session.store.js";

export interface AuthStores {
  followerStore: FollowerStore;
  pairingStore: PairingStore;
  sessionStore: SessionStore;
}

export type LoginResult =
  | { status: "ok"; token: string; expiresAt: string }
  | { status: "invalid" }
  | { status: "locked"; retryAfterSeconds: number };

export class AuthService {
  constructor(private readonly stores: AuthStores) {}

  login(account: string, code: string): LoginResult {
    // Unknown accounts get the same answer as a wrong code, so the API does
    // not reveal which accounts run on this VPS.
    if (this.stores.followerStore.get(account) === null) {
      return { status: "invalid" };
    }

    const result = this.stores.pairingStore.verify(account, code);

    if (result.status !== "ok") {
      return result;
    }

    return { status: "ok", ...this.stores.sessionStore.create(account) };
  }

  logout(token: string): void {
    this.stores.sessionStore.revoke(token);
  }

  logoutAll(account: string): void {
    this.stores.sessionStore.revokeAll(account);
  }
}
