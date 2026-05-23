# Production environment checklist (Render)

Use this when configuring the **carr** web service before store submission.

## Required

| Variable | Example / notes |
|----------|-----------------|
| `APP_ENV` | `production` |
| `SECRET_KEY` | `openssl rand -hex 32` |
| `JWT_SECRET_KEY` | `openssl rand -hex 32` |
| `DATABASE_URL` | Render Postgres connection string (not SQLite) |

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

## App links (listing shares)

| Variable | Notes |
|----------|-------|
| `APPLE_TEAM_ID` | 10-character Apple Team ID |
| `ANDROID_SHA256_CERT_FINGERPRINTS` | Release keystore SHA-256 (comma-separated). Generate locally: `python scripts/print_android_app_link_sha.py` |

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

## Mobile build (Codemagic / local)

- `API_BASE=https://<your-host>` (no `/api` suffix)
- Restrict Google Maps keys to `com.carzo.app` + release SHA-1
- Disclose **Airbridge** in App Store / Play privacy forms

## QA

Run [`REAL_DEVICE_QA.md`](REAL_DEVICE_QA.md) on a **prod** Android build and TestFlight iOS build after env changes.
