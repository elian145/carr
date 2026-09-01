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

### Universal Links & App Links (shared `/listing/<id>` URLs)

So iOS and Android can open **CARZO** from `https://<your-service>.onrender.com/listing/...` (and messengers can verify links), set:

| Key | Value |
|-----|--------|
| `APPLE_TEAM_ID` | Your **10-character** Apple Team ID (same as in the iOS App ID `TEAMID.com.carzo.app`). Required for `/.well-known/apple-app-site-association` to return JSON instead of 404. |
| `ANDROID_SHA256_CERT_FINGERPRINTS` | One or more **SHA-256** certificate fingerprints (colon hex, e.g. from Play App Signing and/or your debug keystore), **comma-separated** with no spaces. Required for `/.well-known/assetlinks.json`. |

After deploy, open in a browser (replace host with yours):

- `https://carr-5hrm.onrender.com/.well-known/apple-app-site-association` → JSON with `applinks`
- `https://carr-5hrm.onrender.com/.well-known/assetlinks.json` → JSON array

**iOS app builds:** In [Apple Developer](https://developer.apple.com) → Identifiers → `com.carzo.app` → **Associated Domains**, enable the capability and include **every** `applinks:` host listed in `ios/Runner/Runner.entitlements` (Render host + `carzo.airbridge.io` + `carzo.abr.ge` if you use Airbridge short links). Xcode **Signing & Capabilities** must match.

Save and trigger a **Manual Deploy**. The service should start and `/health` should return `{"status":"ok"}`.

## Admin dashboard on Render

If you **already created** a web service for the admin dashboard, use the settings below on that service (no second service needed). The blueprint `carr-admin` entry in [`render.yaml`](../render.yaml) is only for new setups — rename `name: carr-admin` to match your existing service name before syncing a blueprint, or ignore the blueprint and configure the dashboard manually.

### Configure your existing admin service

In Render Dashboard → your **admin** web service → **Settings**:

| Setting | Value |
|---------|--------|
| Root directory | `admin-web` |
| Runtime | Node |
| Build command | `npm ci && npm run build` |
| Start command | `npm start` |
| Health check path | `/api/health` |

**Environment** (same tab or Environment):

| Key | Value |
|-----|--------|
| `NEXT_PUBLIC_API_BASE` | `https://carr-5hrm.onrender.com` (your API URL, no trailing slash) |
| `JWT_SECRET_KEY` | **Identical** to the `JWT_SECRET_KEY` on the `carr` API service |
| `NODE_ENV` | `production` |

Then **Manual Deploy** (deploy latest commit from `main` so `/images` and `/api/admin/images` are included).

Verify:

- `https://<your-admin-host>/api/health` → `{"status":"ok","service":"carzo-admin"}`
- `https://<your-admin-host>/login` → sign in with your Render admin account

`JWT_SECRET_KEY` cannot be auto-shared between Render services (secrets). Copy it manually from the API service.

### New service (blueprint)

The repo also includes a **`carr-admin`** web service in [`render.yaml`](../render.yaml) if you prefer blueprint sync instead of a manually created service.
