import path from "node:path";
import { readJsonFile, writeJsonFile } from "../lib/json-file.js";
import {
  DEFAULT_COPY_SETTINGS,
  type FollowerSettingsRecord,
} from "../modules/settings/settings.types.js";

type SettingsChanges = Partial<
  Pick<FollowerSettingsRecord, "copyEnabled" | "stopReason" | "settings">
>;

// Persisted to disk so settings survive an API restart.
export class SettingsStore {
  private readonly filePath: string;
  private readonly records: Record<string, FollowerSettingsRecord>;

  constructor(dataDir: string) {
    this.filePath = path.join(dataDir, "settings.json");
    this.records = readJsonFile<Record<string, FollowerSettingsRecord>>(
      this.filePath,
      {},
    );

    // Fill in settings added after the file was written.
    for (const record of Object.values(this.records)) {
      record.settings = { ...DEFAULT_COPY_SETTINGS, ...record.settings };
    }
  }

  get(account: string): FollowerSettingsRecord | null {
    return this.records[account] ?? null;
  }

  getOrCreate(account: string): FollowerSettingsRecord {
    const existing = this.records[account];

    if (existing !== undefined) {
      return existing;
    }

    const record: FollowerSettingsRecord = {
      copyEnabled: true,
      stopReason: null,
      settings: { ...DEFAULT_COPY_SETTINGS },
      version: 1,
      updatedAt: new Date().toISOString(),
    };
    this.records[account] = record;
    this.persist();
    return record;
  }

  update(account: string, changes: SettingsChanges): FollowerSettingsRecord {
    const current = this.getOrCreate(account);
    const record: FollowerSettingsRecord = {
      ...current,
      ...changes,
      version: current.version + 1,
      updatedAt: new Date().toISOString(),
    };
    this.records[account] = record;
    this.persist();
    return record;
  }

  private persist(): void {
    writeJsonFile(this.filePath, this.records);
  }
}
