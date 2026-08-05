# Production checklist (kk backend)

Use this when deploying to Render or any production environment.

## Required environment variables

Set these **before** deploying; the app validates them in production (`APP_ENV=production`).

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY` | Flask session and CSRF; use a long random string. |
| `JWT_SECRET_KEY` | Signing access/refresh tokens; use a long random string. |
| `DATABASE_URL` | PostgreSQL connection URL (e.g. from Render Postgres). |

## Forgot-password emails

**Render free tier blocks SMTP** (ports 25, 465, 587). Use an API provider instead.

### Option A: Resend (recommended)

Simple API, good deliverability, works on Render free tier. Free tier: 100 emails/day, no credit card.

1. Sign up at [resend.com](https://resend.com) and create an API key.
2. For testing you can use their default sender: set `RESEND_FROM_EMAIL=onboarding@resend.dev`. For production, add and verify your domain in Resend, then set `RESEND_FROM_EMAIL=noreply@yourdomain.com` (or your verified address).
3. In Render → Environment add:
   - `RESEND_API_KEY` = your API key
   - `RESEND_FROM_EMAIL` = `onboarding@resend.dev` (testing) or your verified email/domain
4. For **signup confirmation emails**, set `PUBLIC_BASE_URL` to your API’s public URL (e.g. `https://api.yourdomain.com`). The email will then use an https link that opens in the browser and redirects to the app or shows a fallback; without it, the link is `carzo://` and only works when opened on a device that has the app installed.

### Option B: SendGrid

1. Sign up at [sendgrid.com](https://sendgrid.com), verify a sender, create an API key with “Mail Send”.
2. In Render add `SENDGRID_API_KEY` and `SENDGRID_FROM_EMAIL` (or `MAIL_USERNAME`).

### Option C: SMTP (paid Render or other hosts only)

| Variable | Purpose |
|----------|---------|
| `MAIL_SERVER` | e.g. `smtp.gmail.com`. |
| `MAIL_USERNAME` / `MAIL_PASSWORD` | Gmail: use an [App Password](https://support.google.com/accounts/answer/185833). |
| `MAIL_DEFAULT_SENDER` | Optional. |

Priority: **Resend** → **SendGrid** → **SMTP** (whichever is configured first).

## Security

- **HTTPS only**: Use Render or your host’s TLS; do not serve the API over plain HTTP in production.
- **Rate limiting**: Login, signup, forgot-password, and reset-password are rate-limited per IP (see `kk/security.py` and route decorators).
- **Secrets**: Never commit `SECRET_KEY`, `JWT_SECRET_KEY`, `MAIL_PASSWORD`, `RESEND_API_KEY`, or `SENDGRID_API_KEY`; use the host’s environment (e.g. Render Environment tab).

## Mobile app API keys (Firebase / Google Maps) — restrict them in Console

This cannot be fixed by editing code; it must be done in Google Cloud Console /
Firebase Console by whoever owns the `carzo-prod` project.

**Current state:** `android/app/src/{dev,stage,prod}/google-services.json` register
three separate Android apps (`com.carzo.app`, `com.carzo.app.dev`,
`com.carzo.app.stage`) inside one Firebase project, but all three currently
share the exact same **unrestricted** API key. An unrestricted key extracted
from a `.dev` or `.stage` APK (trivial via `apktool`/`strings`) can be reused
against the `prod` app's package name, or against unrelated Google APIs
enabled on the same project (Maps, etc.), racking up usage on your billing
account.

Fix, per key, in [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials?project=carzo-prod):

1. For each Android API key (one per `google-services.json` "app"), open it and
   under **Application restrictions** choose **Android apps**, then add the
   exact package name + SHA-1 certificate fingerprint for that build
   (`./gradlew signingReport` prints the SHA-1 for each variant/keystore).
2. Under **API restrictions**, limit each key to only the APIs that flavor
   actually needs (Firebase Installations/Cloud Messaging, Maps SDK for
   Android, Places API, etc.) — not "Don't restrict key".
3. If you want leaked dev/stage keys to be independently revocable without
   touching prod, create a **new** key per app in Credentials, restrict it as
   above, then paste it into that flavor's `google-services.json` (the
   `api_key[].current_key` field) instead of sharing prod's key.
4. Repeat the same "Application restrictions → iOS apps (bundle ID)" step for
   the key inside `ios/Runner/GoogleService-Info.plist` (`API_KEY` field).
5. The Google Maps key in `local.properties`
   (`GOOGLE_MAPS_API_KEY`, wired into `AndroidManifest.xml` via
   `manifestPlaceholders["GOOGLE_MAPS_API_KEY"]`) should get the same Android
   app restriction; use a separate Maps-only key per flavor if you want dev
   traffic isolated from prod's Maps quota.

The Gradle side already picks the right file automatically per flavor
(`com.google.gms.google-services` reads `src/<flavor>/google-services.json`
when present) — once the keys above are restricted/rotated, no app code
changes are needed.

## Optional

- **Redis** (`REDIS_URL`): Improves rate limiting and Socket.IO across workers.
- **Sentry** (`SENTRY_DSN`): Error tracking in production.
- **R2 / S3**: For presigned image uploads; see `.env.example`.

## Quick check

1. Set `APP_ENV=production` and all required env vars.
2. **For password reset emails (Render free tier):** Add `RESEND_API_KEY` and `RESEND_FROM_EMAIL=onboarding@resend.dev` (or your verified domain email). Alternatively use `SENDGRID_API_KEY`. SMTP does not work on Render free tier. Logs show which provider is configured at startup.
3. Deploy; confirm health/root endpoint returns 200.
4. Test signup → login → forgot-password with a **real email** (the account must have an email, not just phone). Check inbox and spam for the reset code.
