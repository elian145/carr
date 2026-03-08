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

## Optional

- **Redis** (`REDIS_URL`): Improves rate limiting and Socket.IO across workers.
- **Sentry** (`SENTRY_DSN`): Error tracking in production.
- **R2 / S3**: For presigned image uploads; see `.env.example`.

## Quick check

1. Set `APP_ENV=production` and all required env vars.
2. **For password reset emails (Render free tier):** Add `RESEND_API_KEY` and `RESEND_FROM_EMAIL=onboarding@resend.dev` (or your verified domain email). Alternatively use `SENDGRID_API_KEY`. SMTP does not work on Render free tier. Logs show which provider is configured at startup.
3. Deploy; confirm health/root endpoint returns 200.
4. Test signup → login → forgot-password with a **real email** (the account must have an email, not just phone). Check inbox and spam for the reset code.
