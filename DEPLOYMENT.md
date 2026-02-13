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

## Socket.IO scaling (important)

If you run **more than 1 Gunicorn worker**, you **must** configure a Socket.IO message queue:

- Set `SOCKETIO_MESSAGE_QUEUE` (Redis URL) **or** set `REDIS_URL` (production defaults to it).

Without a message queue, chat broadcasts can appear “randomly broken” because each worker is isolated.

`gunicorn.conf.py` defaults `WEB_CONCURRENCY` to:
- `1` when no message queue is configured
- `2` when a message queue is configured

### Recommended production async mode

For many concurrent clients, prefer:

- `SOCKETIO_ASYNC_MODE=eventlet`
- `SOCKETIO_MESSAGE_QUEUE=<redis url>` (or `REDIS_URL`)

`gunicorn.conf.py` will set `worker_class=eventlet` automatically when `SOCKETIO_ASYNC_MODE=eventlet`.

## Recommended Gunicorn commands

### Single instance (recommended baseline)

Run the backend on an internal port (example `:5003`) and put it behind a reverse proxy for HTTPS:

- `APP_ENV=production SOCKETIO_ASYNC_MODE=eventlet gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"`

### Multiple workers (only with Redis message queue)

If you scale workers above 1, you **must** set Redis:

- `REDIS_URL=redis://...`
- optionally `SOCKETIO_MESSAGE_QUEUE=redis://...` (defaults to `REDIS_URL` in production)
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
  - `worker: celery -A kk.tasks.celery_app.celery_app worker --loglevel=info`

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

