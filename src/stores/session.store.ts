import { createHash, randomBytes } from "node:crypto";
import path from "node:path";
import { readJsonFile, writeJsonFile } from "../lib/json-file.js";

interface Session {
  account: string;
  createdAt: string;
  expiresAt: string;
}

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

// Sessions are keyed by token hash, so the file never holds a usable token.
export class SessionStore {
  private readonly filePath: string;
  private readonly sessions: Record<string, Session>;

  constructor(
    dataDir: string,
    private readonly ttlMs: number,
  ) {
    this.filePath = path.join(dataDir, "sessions.json");
    this.sessions = readJsonFile<Record<string, Session>>(this.filePath, {});
  }

  create(account: string): { token: string; expiresAt: string } {
    const token = randomBytes(32).toString("base64url");
    const now = Date.now();
    const session: Session = {
      account,
      createdAt: new Date(now).toISOString(),
      expiresAt: new Date(now + this.ttlMs).toISOString(),
    };
    this.sessions[hashToken(token)] = session;
    this.removeExpired();
    this.persist();
    return { token, expiresAt: session.expiresAt };
  }

  // Returns the session's account, or null if the token is unknown or expired.
  resolve(token: string): string | null {
    const key = hashToken(token);
    const session = this.sessions[key];

    if (session === undefined) {
      return null;
    }

    if (Date.parse(session.expiresAt) <= Date.now()) {
      delete this.sessions[key];
      this.persist();
      return null;
    }

    return session.account;
  }

  revoke(token: string): void {
    delete this.sessions[hashToken(token)];
    this.persist();
  }

  revokeAll(account: string): void {
    for (const [key, session] of Object.entries(this.sessions)) {
      if (session.account === account) {
        delete this.sessions[key];
      }
    }

    this.persist();
  }

  private removeExpired(): void {
    const now = Date.now();

    for (const [key, session] of Object.entries(this.sessions)) {
      if (Date.parse(session.expiresAt) <= now) {
        delete this.sessions[key];
      }
    }
  }

  private persist(): void {
    writeJsonFile(this.filePath, this.sessions);
  }
}
