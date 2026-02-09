# Backend (Flask)

Small Flask service used for local development and API proxying.

This proxy is intended for **local development**. For production/public deployments, run the canonical listings backend (`kk/app_new.py`) behind HTTPS and a reverse proxy.

## Endpoints

- `GET /health`: health check
- `/<static/...>`: best-effort static file proxying/serving (see `server.py`)
- `GET|POST|PUT|PATCH|DELETE /api/<path>`: proxies requests to the upstream listings API when `LISTINGS_API_BASE` is set

## Setup

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
cd backend
.\.venv\Scripts\activate
python server.py
```

Environment variables:

```
# Optional: upstream listings API base (no trailing /api)
LISTINGS_API_BASE=http://localhost:5000
PORT=5000
```

Production note:

- Use `APP_ENV=production` on the canonical backend and set `SECRET_KEY` / `JWT_SECRET_KEY`.
- Prefer HTTPS in production; do not proxy auth tokens over plain HTTP.
