import type { FollowerStatus, FollowerSync } from "../modules/follower/follower.types.js";

// Latest report from each follower EA. Rebuilt from the next sync after a restart.
export class FollowerStore {
  private readonly followers = new Map<string, FollowerStatus>();

  set(report: FollowerSync): FollowerStatus {
    const status: FollowerStatus = {
      ...report,
      lastSeenAt: new Date().toISOString(),
    };
    this.followers.set(report.accountNumber, status);
    return status;
  }

  get(account: string): FollowerStatus | null {
    return this.followers.get(account) ?? null;
  }
}
