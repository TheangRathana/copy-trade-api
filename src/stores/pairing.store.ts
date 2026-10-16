import { randomInt, timingSafeEqual } from "node:crypto";

export interface PairingCode {
  code: string;
  expiresAt: string;
}

export type PairingResult =
  | { status: "ok" }
  | { status: "invalid" }
  | { status: "locked"; retryAfterSeconds: number };

interface PairingStoreOptions {
  ttlMs: number;
  maxAttempts: number;
  lockMs: number;
}

// One short-lived, one-time code per follower account, shown on its EA chart.
export class PairingStore {
  private readonly codes = new Map<string, PairingCode>();
  private readonly failures = new Map<
    string,
    { attempts: number; lockedUntil: number }
  >();

  constructor(private readonly options: PairingStoreOptions) {}

  getOrCreate(account: string): PairingCode {
    const existing = this.codes.get(account);

    if (existing !== undefined && Date.parse(existing.expiresAt) > Date.now()) {
      return existing;
    }

    const pairing: PairingCode = {
      code: randomInt(0, 1_000_000).toString().padStart(6, "0"),
      expiresAt: new Date(Date.now() + this.options.ttlMs).toISOString(),
    };
    this.codes.set(account, pairing);
    return pairing;
  }

  verify(account: string, code: string): PairingResult {
    const failure = this.failures.get(account);

    if (failure !== undefined && failure.lockedUntil > Date.now()) {
      return {
        status: "locked",
        retryAfterSeconds: Math.ceil((failure.lockedUntil - Date.now()) / 1000),
      };
    }

    const pairing = this.codes.get(account);
    const valid =
      pairing !== undefined &&
      Date.parse(pairing.expiresAt) > Date.now() &&
      code.length === pairing.code.length &&
      timingSafeEqual(Buffer.from(code), Buffer.from(pairing.code));

    if (!valid) {
      this.recordFailure(account);
      return { status: "invalid" };
    }

    // One-time use: the EA shows a fresh code on its next sync.
    this.codes.delete(account);
    this.failures.delete(account);
    return { status: "ok" };
  }

  private recordFailure(account: string): void {
    const previous = this.failures.get(account);
    const attempts =
      previous === undefined || previous.lockedUntil > 0
        ? 1
        : previous.attempts + 1;
    const locked = attempts >= this.options.maxAttempts;

    this.failures.set(account, {
      attempts,
      lockedUntil: locked ? Date.now() + this.options.lockMs : 0,
    });

    // A new code after a lock, so a partly guessed code is useless.
    if (locked) {
      this.codes.delete(account);
    }
  }
}
