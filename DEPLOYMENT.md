# Deployment & Environment Guide

This repo has **three** runtime components:

1) **Listings backend (Flask + Socket.IO)**: `kk/`
2) **Optional Celery worker** (background jobs): `kk/`
3) **Optional local proxy** (single API base during local dev): `backend/server.py`

## Canonical entrypoints

- **Production (WSGI)**: `kk.wsgi:app`
  - Example: `gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"`
- **Development Socket.IO runner**: `python -m kk.app_new`
  - Dev-only convenience runner (refuses `APP_ENV=production`)

## Required production environment variables (listings backend)

Set these for `APP_ENV=production`:

- `APP_ENV=production`
- `SECRET_KEY=<long random>`
- `JWT_SECRET_KEY=<long random>`
- `DATABASE_URL=<postgresql://...>` (recommended) **or** `DB_PATH=<path-to-sqlite>`

Recommended for scale:

- `REDIS_URL=redis://...` (rate limiting + JWT blocklist + Celery + Socket.IO queue)
- `SOCKETIO_MESSAGE_QUEUE=redis://...` (optional override; defaults to `REDIS_URL` in production)
- `CORS_ORIGINS=https://yourdomain.com,https://admin.yourdomain.com` (browser clients)
- `LOG_JSON=true` (structured logs)

## Socket.IO scaling (important) — CHAT-1

**Recommended on Render today:** single Gunicorn worker + threaded HTTP.

| Variable | Recommended value | Notes |
|----------|-------------------|--------|
| `WEB_CONCURRENCY` | `1` | Default in `gunicorn.conf.py`. Do **not** raise without sticky sessions. |
| `GUNICORN_THREADS` | unset (default `32`) | Scale concurrent HTTP/API work here. Default raised from 4 (C-1): see "Socket resource limits". |
| `REDIS_URL` | set (Celery / rate limit / JWT blocklist) | Also used as Socket.IO message queue in production. |
| `SOCKETIO_ASYNC_MODE` | unset / `threading` | Must match `gthread`. |
| `SOCKETIO_ALLOW_EVENTLET` | unset | Legacy; the eventlet worker was removed in Gunicorn 26 and this no longer enables anything (gevent break-glass only, with Redis MQ). |

Why not 2 workers by default when Redis exists?

- Redis Socket.IO message queue fans out **broadcasts** across processes.
- Engine.IO **long-polling** sessions are still pinned to the worker that
  created them. Render’s load balancer is **not sticky**, so polling hops
  between workers → intermittent connect failures (local check: ~8/20 with
  2 workers vs 20/20 with 1 worker).
- Flutter keeps `polling` + `websocket` transports because `gthread` may not
  complete a websocket upgrade; forcing websocket-only would break clients.

If you later run `WEB_CONCURRENCY>1` you need **all** of:

1. `REDIS_URL` / `SOCKETIO_MESSAGE_QUEUE` (broadcast fan-out)
2. Sticky sessions for `/socket.io/*` at the load balancer
3. Explicit ops opt-in via `WEB_CONCURRENCY`

### Socket resource limits (C-1)

With `gthread` + threading Socket.IO, **every open socket (and every Engine.IO
long-poll request) pins one Gunicorn thread**. With the former default of 4
threads, four sockets froze the whole REST API. `kk/realtime_limits.py` now
bounds this (per process; the deployment is one worker). All values are
optional environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `GUNICORN_THREADS` | `32` | Threads in the single gthread worker. |
| `SOCKETIO_MAX_CONNECTIONS` | `threads - max(8, threads/2)` (= 16 at 32 threads) | Sockets in total; new ones are refused (`server_busy`) so HTTP always keeps >= half the threads. The app falls back to HTTP polling for chat. |
| `SOCKETIO_ALLOW_ANONYMOUS` | off | Token-less sockets are **refused** (`401 authentication_required` at the WSGI edge, before any Engine.IO session). The app always connects with a bearer token. `1` re-enables guests (then the two guest caps below apply). |
| `SOCKETIO_MAX_CONNECTIONS_PER_USER` | `5` | Per account; the OLDEST socket is evicted (`connection_replaced`) so a reconnect never locks a user out. |
| `SOCKETIO_MAX_GUEST_CONNECTIONS` | `max(1, total/4)` | Credential-less sockets in total. |
| `SOCKETIO_MAX_GUESTS_PER_IP` | `2` | Credential-less sockets per address (authenticated users are not limited per IP: carrier NAT). |
| `SOCKETIO_MAX_HTTP_BUFFER_SIZE` | `65536` | Largest Socket.IO message (engine.io default was 1 MB). |
| `JSON_MAX_CONTENT_LENGTH` | `1048576` | Largest `application/json` request body (413 `payload_too_large`). Multipart uploads keep `MAX_CONTENT_LENGTH`. |

**Edge guard (`kk/socket_edge_guard.py`).** The registry above only sees sockets
that reached the Socket.IO `connect` handler, but under `gthread` an Engine.IO
transport pins a thread *before* that, and a refused CONNECT leaves the
transport open. Reproduced on real Gunicorn: 32 raw websockets that never sent
CONNECT (or 16 transports kept open after `server_busy`) froze `/api/cars`.
A WSGI middleware in front of Socket.IO therefore (1) returns a cheap `401` for
new sessions/upgrades without a *signed* access JWT (expired-but-signed tokens
pass so the `token_expired` -> refresh flow still works), (2) holds one slot per
in-flight `/socket.io` request and answers `503 server_busy` + `Retry-After`
above `min(total + max(2, total/4), threads - 2)` (20 at 32 threads), so REST
always keeps at least two threads whatever `GUNICORN_THREADS` is, and (3) closes
Engine.IO sessions with no Socket.IO connection after
`SOCKETIO_AUTH_DEADLINE_SECONDS` (default `10`, `0` disables).
**If Render still has `GUNICORN_THREADS=4`** the service stays up: 2 realtime
requests at most (1 engaged socket), REST keeps 2 threads, everything else gets
503 and the app polls over REST; a boot warning is logged. Set it to `32`.

Socket events are rate limited too: `send_message` 20 per 10 s per socket and
120 per 10 min per user (same budget as `POST /api/chat/<id>/send`),
`join_chat` 30/min, `typing_*` 20 per 10 s, `leave_chat` 60/min; over-limit
`send_message`/`join_chat` get an `error` event with `code: rate_limited` and
`retry_after`.

**Capacity is spent on conversations, not on logged-in users.** The app opens
one socket per signed-in session, but a socket only matters while its user is
inside a chat conversation: text is always sent over REST, offline users get FCM
push, and the chat screen falls back to a 12 s REST poll whenever the socket is
down. So a socket that has joined no conversation is *idle*:

| Variable | Default | Effect |
|----------|---------|--------|
| `SOCKETIO_IDLE_RELEASE_SECONDS` | `120` | An authenticated socket with no joined conversation is released after this long (`0` disables the sweep). Opening a thread or typing restarts the clock; sending/joining a conversation engages the socket. |
| `SOCKETIO_GUEST_IDLE_SECONDS` | `30` | Same for credential-less sockets (they can never join a conversation). |
| `SOCKETIO_PREEMPT_MIN_IDLE_SECONDS` | `15` | At the total ceiling a new authenticated connection preempts the oldest idle socket (guests first) that has been idle at least this long; engaged sockets are never preempted. |

A released socket receives `connection_released` (`idle` / `capacity`); the app
does not auto-reconnect, it reconnects when the user opens a conversation. A
connection above the ceiling is refused with `server_busy`; the app stops the
transport's retry loop and retries once, only while a conversation is open.
Net effect: the ceiling (16 at 32 threads) bounds *simultaneously engaged chat
users*, not everyone who has the app open, and every session still gets
realtime for ~2 minutes after launch.

Measured with real Gunicorn gthread (see the C-1 report): the old default (4
threads, no caps) froze the whole API at exactly 4 open sockets; with these
settings 40 distinct users connecting, 12 guests, 25 overlapping reconnects and
a 500k-message flood never made an HTTP request slower than ~250 ms.

**Capacity note:** 16 *engaged* conversations is a launch-sized number, not a
growth-sized one. Beyond it chat degrades to REST polling (still correct), and
real scale needs an async worker (gevent, not shipped or load-tested here;
eventlet was removed with Gunicorn 26) or a separate realtime service. Load test before raising
`SOCKETIO_MAX_CONNECTIONS`; watch the `Socket.IO released ... idle` and
`connect refused: server_busy` log lines.

### Recommended production async mode

**Default (required on Render):** leave `SOCKETIO_ASYNC_MODE` unset (or set
`threading`). Gunicorn uses `gthread` and Socket.IO uses `threading`.

Do **not** set `SOCKETIO_ASYNC_MODE=eventlet`. Gunicorn 26 removed the eventlet
worker and the `eventlet` package is no longer installed, so the value is always
ignored: `gunicorn.conf.py` logs a warning and boots `gthread`, and Socket.IO
uses `threading`. After any Gunicorn upgrade re-run
`python scripts/c1_edge_load_check.py` (Linux) against real Gunicorn.

## Recommended Gunicorn commands

### Single instance (recommended baseline)

Run the backend on an internal port (example `:5003`) and put it behind a reverse proxy for HTTPS:

- `APP_ENV=production gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"`
- Keep `WEB_CONCURRENCY=1` and raise `GUNICORN_THREADS` for HTTP concurrency.
- Keep `REDIS_URL` for Celery / rate limits; do not enable eventlet.

### Multiple workers (only with Redis MQ **and** sticky sessions)

If you scale workers above 1:

- `REDIS_URL=redis://...`
- optionally `SOCKETIO_MESSAGE_QUEUE=redis://...` (defaults to `REDIS_URL` in production)
- sticky sessions for `/socket.io/*`
- then set `WEB_CONCURRENCY=2` (or more) and restart.

## Reverse proxy (Nginx) example

In production you should serve everything from one HTTPS origin:

- REST API: `/api/*`
- Socket.IO: `/socket.io/*`
- Static media (uploads): `/static/*`

Example Nginx server block (trim to your needs):

```nginx
server {
  listen 443 ssl http2;
  server_name yourdomain.com;

  # TLS config omitted here.

  client_max_body_size 25m;

  location /api/ {
    proxy_pass http://127.0.0.1:5003;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  location /static/ {
    proxy_pass http://127.0.0.1:5003;
    proxy_set_header Host $host;
  }

  # Socket.IO (websocket + long-polling)
  location /socket.io/ {
    proxy_pass http://127.0.0.1:5003;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 65s;
  }
}
```

Notes:
- If you use Cloudflare, ensure WebSockets are enabled and timeouts are compatible.
- If you have multiple app servers behind a load balancer, you still need Redis MQ for Socket.IO broadcasts.

## Celery worker (background jobs)

If you enable async image jobs (e.g. `?async=1`), run a worker:

- Procfile entry:
  - `worker: celery -A kk.tasks.celery_app.celery_app worker --loglevel=info --concurrency=2 --max-tasks-per-child=50 --max-memory-per-child=200000`

Workers reuse one Flask app per process (`FlaskContextTask` / `get_celery_flask_app`) so tasks do not call `create_app()` on every job.

BE-13: on a 512 MB Render instance, Celery's default concurrency (`multiprocessing.cpu_count()`) can reflect the *host* machine's core count rather than this instance's actual allocation, spawning far more prefork children than 512 MB can hold (each child rebuilds the full Flask app and, for image tasks, loads OpenCV/NumPy/Pillow/boto3). Keep `--concurrency` low (2) and `--max-tasks-per-child`/`--max-memory-per-child` set so child processes are recycled instead of the whole instance being OOM-killed.

Minimum env:
- `REDIS_URL=redis://...` (recommended; memory broker is dev-only)

## Local development (typical)

### Option A: run backend directly (recommended)

- Listings backend:
  - `APP_ENV=development`
  - `python -m kk.app_new`

### Option B: run proxy + backend (if your app expects one base URL)

- Start listings backend (example port 5000)
- Start proxy (example port 5003):
  - `backend/env.local` (or env vars):
    - `LISTINGS_API_BASE=http://127.0.0.1:5000`

## Environment files in this repo

- `kk/.env.example`: listings backend + Celery variables
- `backend/.env.example`: local proxy variables
- `.env.example`: SMS provider example variables

Do **not** commit real secrets; use a secret manager or CI-provided env vars.

## Deploy to Render (or similar PaaS)

1. **New Web Service**
   - Connect this repo; set root directory if needed.
   - Build command: `pip install -r kk/requirements.txt`
   - **Start command (required):** use **one** of:
     - `bash start_render.sh`   (recommended; uses script in repo)
     - `gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"`
   - **Do not use** `--chdir kk` or `app_new:app` — that breaks imports and causes `ImportError: attempted relative import with no known parent package`.

2. **Environment**
   - Set `APP_ENV=production`, `SECRET_KEY`, `JWT_SECRET_KEY`.
   - Set `DATABASE_URL` (e.g. Render PostgreSQL) or `DB_PATH` for SQLite.
   - For Socket.IO and scaling: set `REDIS_URL` (e.g. Render Redis). Leave `SOCKETIO_ASYNC_MODE` unset (or `threading`). Do not set `eventlet`.
   - Set `CORS_ORIGINS` to your frontend origin(s).

3. **Optional worker**
   - Add a **Background Worker** with start command:  
     `celery -A kk.tasks.celery_app.celery_app worker --loglevel=info --concurrency=2 --max-tasks-per-child=50 --max-memory-per-child=200000`
     and the same env vars (including `REDIS_URL`). On a 512 MB instance, keep `--concurrency` low (see BE-13 note above) to avoid OOM.

4. **Cloudflare**
   - If you put Render behind Cloudflare, enable WebSockets and use timeouts ≥ 65s for `/socket.io/`.

