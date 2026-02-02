# Backend (Flask)

Small Flask service used for local development and API proxying.

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
