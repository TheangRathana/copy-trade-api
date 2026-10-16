import path from "node:path";

const LOOPBACK_IPS = ["127.0.0.1", "::1", "::ffff:127.0.0.1"];

function parseList(value: string | undefined): string[] | null {
  if (value === undefined || value.trim() === "") {
    return null;
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export const config = {
  // Each instance keeps its own data so two instances never share a file.
  dataDir: path.resolve(
    process.env.DATA_DIR ?? path.join("data", process.env.PORT ?? "4000"),
  ),
  // IPs allowed to call the EA endpoints. "*" allows any IP.
  eaAllowedIps: parseList(process.env.EA_ALLOWED_IPS) ?? LOOPBACK_IPS,
  masterOnlineMs: 10_000,
  followerOnlineMs: 10_000,
  pairingCodeTtlMs: 5 * 60_000,
  pairingMaxAttempts: 5,
  pairingLockMs: 15 * 60_000,
  sessionTtlMs: 30 * 24 * 60 * 60_000,
  commandTtlMs: 60_000,
  commandHistoryMs: 60 * 60_000,
} as const;
