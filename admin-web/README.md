# CARZO Admin Web Dashboard

Browser-based admin dashboard for the CARZO car marketplace. Connects to the existing Flask API (`/api/admin/*`).

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

Deploy this folder to **Vercel**, **Netlify**, or **Cloudflare Pages**:

| Setting | Value |
|---------|--------|
| Root directory | `admin-web` |
| Build command | `npm run build` |
| Output | Next.js default |
| Env var | `NEXT_PUBLIC_API_BASE=https://your-api.onrender.com` |

Then add the deployed admin URL to `CORS_ORIGINS` on the API service.

## Auth

- Login: `POST /api/auth/login`
- Session: JWT stored in `localStorage`
- Every page checks `GET /api/auth/me` for `is_admin: true`
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
