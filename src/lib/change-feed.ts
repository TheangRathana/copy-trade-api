import { EventEmitter, once } from "node:events";

// Wakes follower syncs that are waiting for something new (long polling):
// a change in their master's positions, or new settings / a command for the
// follower itself.
export class ChangeFeed {
  private readonly emitter = new EventEmitter();

  constructor() {
    // One waiting listener pair per connected follower
    this.emitter.setMaxListeners(0);
  }

  notifyMaster(masterAccount: string): void {
    this.emitter.emit(`master:${masterAccount}`);
  }

  notifyAccount(account: string): void {
    this.emitter.emit(`account:${account}`);
  }

  // Resolves on the first change for the follower or its master, or after
  // timeoutMs. masterAccount is null when the follower has no master.
  async waitFor(
    account: string,
    masterAccount: string | null,
    timeoutMs: number,
  ): Promise<void> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const events = [`account:${account}`];
    if (masterAccount !== null) events.push(`master:${masterAccount}`);

    try {
      await Promise.race(
        events.map((event) => once(this.emitter, event, { signal: controller.signal })),
      );
    } catch {
      // Timed out: nothing changed
    } finally {
      clearTimeout(timer);
      // Removes the listeners that didn't fire
      controller.abort();
    }
  }
}
