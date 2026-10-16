import { randomUUID } from "node:crypto";

export type CommandType = "CLOSE_POSITION" | "CLOSE_ALL";
export type CommandStatus = "pending" | "done" | "failed" | "expired";

export interface Command {
  id: string;
  account: string;
  type: CommandType;
  ticket: string | null;
  status: CommandStatus;
  error: string | null;
  createdAt: string;
  completedAt: string | null;
}

interface CommandStoreOptions {
  // A pending command older than this is never sent to the EA again.
  ttlMs: number;
  // Finished commands are kept this long for the UI.
  historyMs: number;
}

export class CommandStore {
  private readonly commands = new Map<string, Command>();

  constructor(private readonly options: CommandStoreOptions) {}

  create(account: string, type: CommandType, ticket: string | null): Command {
    this.prune();

    const command: Command = {
      id: randomUUID(),
      account,
      type,
      ticket,
      status: "pending",
      error: null,
      createdAt: new Date().toISOString(),
      completedAt: null,
    };
    this.commands.set(command.id, command);
    return command;
  }

  get(id: string): Command | null {
    const command = this.commands.get(id);
    return command === undefined ? null : this.expireIfStale(command);
  }

  listPending(account: string): Command[] {
    return this.list(account).filter((command) => command.status === "pending");
  }

  // Newest first.
  list(account: string): Command[] {
    return [...this.commands.values()]
      .filter((command) => command.account === account)
      .map((command) => this.expireIfStale(command))
      .reverse();
  }

  complete(
    id: string,
    status: "done" | "failed",
    error: string | null,
  ): Command | null {
    const command = this.commands.get(id);

    if (command === undefined) {
      return null;
    }

    // An ack can still arrive after the command expired; the EA result wins.
    command.status = status;
    command.error = error;
    command.completedAt = new Date().toISOString();
    return command;
  }

  private expireIfStale(command: Command): Command {
    if (
      command.status === "pending" &&
      Date.now() - Date.parse(command.createdAt) > this.options.ttlMs
    ) {
      command.status = "expired";
      command.completedAt = new Date().toISOString();
    }

    return command;
  }

  private prune(): void {
    const cutoff = Date.now() - this.options.historyMs;

    for (const [id, command] of this.commands) {
      if (Date.parse(command.createdAt) < cutoff) {
        this.commands.delete(id);
      }
    }
  }
}
