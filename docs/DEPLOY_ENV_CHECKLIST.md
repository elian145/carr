# Production environment checklist (Render)

Use this when configuring the **carr** web service before store submission.

## Required

| Variable | Example / notes |
|----------|-----------------|
| `APP_ENV` | `production` |
| `SECRET_KEY` | `openssl rand -hex 32` |
| `JWT_SECRET_KEY` | `openssl rand -hex 32` |
| `DATABASE_URL` | Render Postgres connection string (not SQLite) |
| `REDIS_URL` | Render Key Value / Redis URL — **required** for shared rate limits across Gunicorn workers |
| `JWT_ACCESS_TOKEN_MINUTES` | Optional; default **30** (clamped 15–60). Short access JWT; clients use refresh rotation |

Without `REDIS_URL`, the API refuses to start (unless emergency `ALLOW_INMEMORY_RATE_LIMITS=1`).
Confirm `/health` shows `"redis_configured": true`.

## Uploads (pick one)

### Option A — Cloudflare R2 (recommended)

| Variable | Notes |
|----------|-------|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API token |
| `R2_SECRET_ACCESS_KEY` | R2 API token |
| `R2_BUCKET_NAME` | Bucket name |
| `R2_PUBLIC_URL` | Public base URL (`https://pub-….r2.dev` or custom domain) |

After deploy: upload a listing photo, redeploy again, confirm the photo URL still loads.

### Option B — Render persistent disk

| Variable | Notes |
|----------|-------|
| Mount disk | e.g. `/data` on the web service |
| `UPLOAD_FOLDER` | `/data/uploads` |

See [`kk/docs/UPLOAD_PERSISTENCE.md`](../kk/docs/UPLOAD_PERSISTENCE.md).

After deploy, confirm `/health` shows `"upload_persistence":"r2"` or `"disk"`, or run:

```bash
python scripts/verify_production_host.py --host https://<your-host> --require-upload-persistence
```

Do **not** set `ALLOW_EPHEMERAL_UPLOADS=1` for store launches (escape hatch only).

## App links (listing shares)

| Variable | Notes |
|----------|-------|
| `APPLE_TEAM_ID` | 10-character Apple Team ID |
| `ANDROID_SHA256_CERT_FINGERPRINTS` | Release keystore SHA-256 (comma-separated). Generate locally: `python scripts/print_android_app_link_sha.py` |
| `LISTING_REQUIRE_APPROVAL` | `1`/`true` to force new listings into `pending` until admin activates (default **on** when `APP_ENV=production`) |
| `MIN_APP_VERSION` / `MIN_ANDROID_BUILD` / `MIN_IOS_BUILD` | Optional force-update gates (also editable in admin Settings) |

Verify:

- `https://<your-host>/.well-known/assetlinks.json` → 200
- `https://<your-host>/.well-known/apple-app-site-association` → 200

Or run: `python scripts/verify_production_host.py --host https://<your-host> --require-app-links`

## Push notifications (chat alerts)

| Variable | Notes |
|----------|-------|
| `FIREBASE_SERVICE_ACCOUNT_BASE64` | **Recommended on Render.** Run `python scripts/format_firebase_service_account_json.py service-account.json`, then paste **`firebase-service-account-base64.txt`** (one short line). |
| `FIREBASE_SERVICE_ACCOUNT` | Alternative: raw JSON one line (Render UI may wrap visually). |
| `GOOGLE_APPLICATION_CREDENTIALS` | Alternative: path to JSON via Render **Secret File** (e.g. `/etc/secrets/firebase-sa.json`). |

After deploy, `/health/push` must show `"credentials_oauth_ok": true`.
| Firebase Console → Project Settings → Cloud Messaging | Upload **Apple APNs key** (.p8) so FCM can deliver to iPhones |

If chat works in-app but no phone banner: check Render logs for `no firebase_token` (user must open app while logged in after this fix) or `FCM send failed` (bad credentials / APNs).

## Recommended

| Variable | Notes |
|----------|-------|
| `SENTRY_DSN` | Backend error tracking |
| `PRIVACY_URL` | Live privacy policy (required for stores + Airbridge) |
| `TERMS_URL` | Terms of service |
| `CORS_ORIGINS` | Your web/admin origins only |

## Admin web (`admin-web`)

| Variable | Notes |
|----------|-------|
| `NEXT_PUBLIC_API_BASE` / `API_PROXY_TARGET` | Flask API origin for the server-side proxy |
| `JWT_SECRET_KEY` | **Same value as Flask.** Required in production so middleware can verify the httpOnly `carzo_admin_jwt` session cookie |

Admin login uses `POST /api/admin-session` (JWT never stored in `localStorage`).

## Mobile build (Codemagic / local)

- `API_BASE=https://<your-host>` (no `/api` suffix)
- Optional crash reporting: `--dart-define=SENTRY_DSN=https://…` (Flutter; see `lib/services/config.dart` and `lib/app/bootstrap.dart`)
- Restrict Google Maps keys to `com.carzo.app` + release SHA-1
- Disclose **Airbridge** in App Store / Play privacy forms

## Preflight commands

```bash
# Static only (CI runs this)
python scripts/verify_publish_ready.py

# Static + deployed API smoke (recommended before each store upload)
python scripts/verify_preflight.py --host https://<your-host>

# Fail if Android App Links are not configured yet
python scripts/verify_preflight.py --host https://<your-host> --require-app-links
```

Android App Links fingerprint helper:

```bash
python scripts/print_android_app_link_sha.py
# Paste output into Render → ANDROID_SHA256_CERT_FINGERPRINTS → redeploy
```

## Production App Links status (re-check before Play upload)

As of 2026-07-21 against `https://carr-5hrm.onrender.com`:

- iOS Universal Links (AASA): configured (`APPLE_TEAM_ID` set) → 200
- Android App Links (`assetlinks.json`): configured (`ANDROID_SHA256_CERT_FINGERPRINTS` set) → 200

Re-verify anytime:

```bash
python scripts/print_android_app_link_sha.py --verify-host https://carr-5hrm.onrender.com
python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com --require-app-links
```

Run [`REAL_DEVICE_QA.md`](REAL_DEVICE_QA.md) on a **prod** Android build and TestFlight iOS build after env changes.
