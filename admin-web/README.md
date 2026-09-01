# CarNet Admin Web Dashboard

Browser-based admin dashboard for the CarNet car marketplace. Connects to the existing Flask API (`/api/admin/*`).

## Features

- **Dashboard** — platform KPIs, moderation queue, activity chart, recent activity
- **Users** — search, paginate, export CSV, user detail pages
- **Listings** — browse, filter page, export CSV, open public listing links
- **Reports** — moderate with optional admin notes, view listing links
- **Dealers** — approve or reject pending dealer applications
- **Messages** — recent chat activity
- **Notifications** — in-app notification feed
- **Audit log** — filter by action type

## Prerequisites

1. Flask API running (local or production)
2. An admin account (`is_admin = true` in the database)

Grant admin locally:

```powershell
python kk/scripts/set_admin_by_phone.py YOUR_PHONE_NUMBER
```

## Setup

```powershell
cd admin-web
copy .env.example .env.local
npm install
```

Edit `.env.local`:

```env
NEXT_PUBLIC_API_BASE=http://localhost:5000
```

Use your production API URL when deploying (no trailing slash).

## Development

```powershell
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) and sign in with an admin account (email/phone/username + password).

### CORS

The browser will block API calls unless the Flask server allows your admin origin.

**Local:**

```env
CORS_ORIGINS=http://localhost:3000
```

**Production (Render):**

```env
CORS_ORIGINS=https://admin.yourdomain.com
```

Restart the API after changing `CORS_ORIGINS`.

## Production deploy

### Render (recommended for this repo)

The root [`render.yaml`](../render.yaml) defines a **`carr-admin`** Node service alongside the Flask API (`carr`).

1. In Render Dashboard → **Blueprint** → sync from repo (or create the `carr-admin` web service manually).
2. Set **`JWT_SECRET_KEY`** on **carr-admin** to the **same value** as the `carr` API service (required for session cookies).
3. `NEXT_PUBLIC_API_BASE` is wired to the API’s `RENDER_EXTERNAL_URL` in the blueprint.
4. After deploy, open `https://<carr-admin-host>/api/health` → `{"status":"ok"}`.
5. Sign in at `https://<carr-admin-host>/login`.

Manual service settings if not using the blueprint:

| Setting | Value |
|---------|--------|
| Root directory | `admin-web` |
| Runtime | Node |
| Build command | `npm ci && npm run build` |
| Start command | `npm start` |
| Health check | `/api/health` |
| `NEXT_PUBLIC_API_BASE` | `https://carr-5hrm.onrender.com` (your API URL) |
| `JWT_SECRET_KEY` | Same as Flask API |

### Vercel / Netlify / Cloudflare Pages

Deploy this folder to **Vercel**, **Netlify**, or **Cloudflare Pages**:

| Setting | Value |
|---------|--------|
| Root directory | `admin-web` |
| Build command | `npm run build` |
| Output | Next.js default |
| Env var | `NEXT_PUBLIC_API_BASE=https://your-api.onrender.com` |
| Env var (**required in prod**) | `JWT_SECRET_KEY=<same secret as the Flask API>` — used to verify admin session JWTs. If unset in production, session resolution fails closed (all page auth breaks). |

Then add the deployed admin URL to `CORS_ORIGINS` on the API service (only needed if the browser calls the API directly; the `/backend-api` proxy avoids CORS for most admin calls).

## Auth

- Login: `POST /api/admin-session` (Next route → Flask login; JWT never exposed to JS)
- Session: httpOnly cookies `carzo_admin_jwt` (access) + `carzo_admin_refresh` (refresh); middleware/proxy rotate short-lived access tokens
- API calls: `/backend-api/*` proxy attaches `Authorization: Bearer …` from the access cookie (refreshing when expired)
- Client also checks `GET /api/auth/me` for `is_admin: true`
- Non-admin accounts are rejected at login

## Project structure

```
admin-web/
  src/
    app/           # Next.js pages (App Router)
    components/    # UI building blocks
    context/       # Auth provider
    lib/           # API client, types, formatters
```
