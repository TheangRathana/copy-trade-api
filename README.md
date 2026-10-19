# Copy Trade API

## Docker (production server)

```sh
cp .env.example .env    # set ADMIN_API_KEY and REDIS_URL
docker compose up -d --build
```

The API listens on `127.0.0.1:4200` only; put nginx with HTTPS in front of it.
Settings, sessions and accounts are kept in the `api-data` volume.

## Local development

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Local development defaults to `127.0.0.1:4000`. Set `HOST` and `PORT` to override
the listening address.

## API

Interactive docs (Swagger UI) at `/docs`, OpenAPI spec at `/docs/json`. They are
generated from the same zod schemas the API validates with.

All responses are `{ success, data }` or `{ success: false, error, issues? }`.

### EA endpoints (localhost only)

Only requests from `127.0.0.1` / `::1` are accepted. Set `EA_ALLOWED_IPS`
(comma-separated, or `*`) to allow other IPs, for example when running in Docker.

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/master/state` | Master EA posts its positions (registered masters only) |
| POST | `/api/follower/sync` | Follower EA reports status; gets master state, settings, pending commands and its pairing code |
| POST | `/api/follower/commands/:id/ack` | Follower EA reports a command result (`done` / `failed`) |

### Admin endpoints (masters and followers)

Set `ADMIN_API_KEY` in the API's environment and send it as
`Authorization: Bearer <ADMIN_API_KEY>`. Without the variable the admin API is
off (503). Each follower copies exactly one master; a master only posts state
once it is registered, and an unregistered follower copies nothing.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/admin/masters` | All masters, with online status and follower count |
| POST | `/api/admin/masters` | `{ accountNumber, name, note?, enabled? }` Add a master |
| GET | `/api/admin/masters/:account` | One master and its followers |
| PATCH | `/api/admin/masters/:account` | `{ name?, note?, enabled? }` `enabled: false` stops copying it |
| DELETE | `/api/admin/masters/:account` | Only when it has no followers |
| GET | `/api/admin/followers?masterAccount=` | All followers, or one master's |
| POST | `/api/admin/followers` | `{ accountNumber, masterAccount, name, note? }` Add a follower |
| GET | `/api/admin/followers/:account` | One follower, with its settings and status |
| PATCH | `/api/admin/followers/:account` | `{ masterAccount?, name?, note? }` Move it to another master |
| DELETE | `/api/admin/followers/:account` | Also removes its settings and logs out its sessions |

Masters and followers are stored in **Redis** when `REDIS_URL` is set (for
example `rediss://default:PASSWORD@host:25061/2`), otherwise in
`DATA_DIR/accounts.json`. All keys start with `ct:`:

| Key | Type | Content |
|---|---|---|
| `ct:masters` | SET | All master account numbers |
| `ct:master:{acct}` | HASH | `accountNumber`, `name`, `note`, `enabled` (1/0), `createdAt`, `updatedAt` |
| `ct:master:{acct}:followers` | SET | Accounts following this master |
| `ct:followers` | SET | All follower account numbers |
| `ct:follower:{acct}` | HASH | `accountNumber`, `masterAccount`, `name`, `note`, `createdAt`, `updatedAt` |

`GET /api/health` reports `storage` (`redis` or `file`) and answers 503 when
Redis is set but not reachable.

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

The EA has one input, `Enabled`. The API address (`http://127.0.0.1:4000`),
sync interval (250 ms) and magic number (26090201) are fixed in the code. Copy
and risk settings come from the API and are changed in the web dashboard. Add
`http://127.0.0.1:4000` to MT5's WebRequest allowlist (Tools → Options →
Expert Advisors).

- **Symbol = the chart's symbol.** Attach the Master EA to the XAUUSD chart: it
  only sends XAUUSD positions. Attach each follower to its broker's gold chart
  (XAUUSD, XAUUSDs, XAUUSD.pro …): copies open on that chart's symbol, so no
  symbol mapping is needed. Master trades on a different instrument are ignored.
- The chart panel shows the 6-digit **Dashboard Code** used to log in, and the
  risk settings in use: lot size, BUY/SELL/SL/TP, max positions and daily loss.
- **Fast copying.** The Master EA sends the moment a trade opens, closes or its
  SL/TP changes (`OnTradeTransaction`). The follower's sync is long-polled: when
  it is up to date the API holds the request for up to 1.5 s and answers as soon
  as the master's positions, its settings or a dashboard command change, so a
  master trade reaches the follower within a few milliseconds.
- When copying is off, no new trades open; copied trades still follow the master's closes and SL/TP.
- A copied trade closed from the dashboard is not copied again while the master position stays open.
- `Enabled = false` keeps the EA reporting to the dashboard but stops all trading and commands.
