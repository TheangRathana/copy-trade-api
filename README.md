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
