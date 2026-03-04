# Render setup

If your deploy **exits with status 1** and the build succeeded, the failure is at **startup**. Check the **full deploy log** for the Python traceback.

## Most common cause: missing secrets

The app requires these in **production** (Render sets `APP_ENV=production` or it defaults to production):

1. **SECRET_KEY** – long random string (e.g. run `openssl rand -hex 32` locally and paste).
2. **JWT_SECRET_KEY** – another long random string.

**Where to set them:** Render Dashboard → your Web Service → **Environment** → Add Variable (mark as **Secret**).

Add:

| Key             | Value                    | Secret? |
|-----------------|--------------------------|--------|
| `APP_ENV`       | `production`             | No     |
| `SECRET_KEY`    | (e.g. from `openssl rand -hex 32`) | Yes |
| `JWT_SECRET_KEY`| (e.g. from `openssl rand -hex 32`) | Yes |

Optional:

- **DATABASE_URL** – Postgres connection string if you use Render Postgres. If unset, the app uses SQLite (data is lost on redeploy).
- **CORS_ORIGINS** – e.g. `https://your-app.com` if you have a web frontend.

Save and trigger a **Manual Deploy**. The service should start and `/health` should return `{"status":"ok"}`.
