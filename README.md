# Copy Trade API

## Docker

Start two API instances with Docker Compose:

```sh
docker compose up --build -d
```

The instances are available at:

- http://localhost:4001/api/health
- http://localhost:4002/api/health

Both containers listen on port 4000 internally and bind to `0.0.0.0`.
Docker publishes them on host ports 4001 and 4002.

Each instance stores its master state in memory independently. Send a master and
its followers to the same port. State is cleared when its container restarts.

Check status and logs:

```sh
docker compose ps
docker compose logs -f
```

Stop both instances:

```sh
docker compose down
```

## Local development

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Local development defaults to `127.0.0.1:4000`. Set `HOST` and `PORT` to override
the listening address.

## API

All responses are `{ success, data }` or `{ success: false, error, issues? }`.

### EA endpoints (localhost only)

Only requests from `127.0.0.1` / `::1` are accepted. Set `EA_ALLOWED_IPS`
(comma-separated, or `*`) to allow other IPs, for example when running in Docker.

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/master/state` | Master EA posts its positions |
| GET | `/api/master/state` | Latest master state |
| POST | `/api/follower/sync` | Follower EA reports status; gets master state, settings, pending commands and its pairing code |
| POST | `/api/follower/commands/:id/ack` | Follower EA reports a command result (`done` / `failed`) |

### UI endpoints

Log in with the account number and the 6-digit pairing code shown on that
follower's EA chart. The code expires after 5 minutes, works once, and the
account is locked for 15 minutes after 5 wrong codes. Send the returned token as
`Authorization: Bearer <token>`. A session only controls its own account.

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/auth/login` | `{ accountNumber, pairingCode }` → `{ token, expiresAt }` |
| POST | `/api/auth/logout` | Revoke this token |
| POST | `/api/auth/logout-all` | Revoke every session for this account |
| GET | `/api/dashboard/account` | Status, balance, positions, copy state, settings |
| PATCH | `/api/dashboard/settings` | Change copy / risk settings (partial) |
| POST | `/api/dashboard/copy/start` | Start copying |
| POST | `/api/dashboard/copy/stop` | `{ closeAll?: boolean }` Stop copying |
| POST | `/api/dashboard/commands` | `{ type: "CLOSE_POSITION", ticket }` or `{ type: "CLOSE_ALL" }` |
| GET | `/api/dashboard/commands` | Recent commands |
| GET | `/api/dashboard/commands/:id` | Command status: `pending` / `done` / `failed` / `expired` |

Settings and sessions are saved under `DATA_DIR` (default `data/<PORT>`), so
they survive a restart. Master state, follower status and commands are in memory.

## Follower EA (`mt5/Copy AiO.mq5`)

The EA now has only three inputs: `ApiBaseUrl` (default `http://127.0.0.1:4000`),
`SyncIntervalMs` and `Enabled`. Copy and risk settings come from the API and are
changed in the web dashboard. Add `ApiBaseUrl` to MT5's WebRequest allowlist
(Tools → Options → Expert Advisors).

- The chart panel shows the 6-digit **Dashboard Code** used to log in.
- When copying is off, no new trades open; copied trades still follow the master's closes and SL/TP.
- A copied trade closed from the dashboard is not copied again while the master position stays open.
- `Enabled = false` keeps the EA reporting to the dashboard but stops all trading and commands.
