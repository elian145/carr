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

To send password reset emails (required for email-based accounts):

| Variable | Purpose |
|----------|---------|
| `MAIL_SERVER` | SMTP server (e.g. `smtp.gmail.com`). |
| `MAIL_PORT` | Usually `587` for TLS. |
| `MAIL_USE_TLS` | `true`. |
| `MAIL_USERNAME` | Sender email (e.g. your Gmail). |
| `MAIL_PASSWORD` | For Gmail: use an [App Password](https://support.google.com/accounts/answer/185833), not your normal password. |
| `MAIL_DEFAULT_SENDER` | Optional; e.g. `"CARZO <your@gmail.com>"`. |

If these are not set, forgot-password still returns 200 but **no email is sent** (users with only email will not receive a reset link).

## Security

- **HTTPS only**: Use Render or your host’s TLS; do not serve the API over plain HTTP in production.
- **Rate limiting**: Login, signup, forgot-password, and reset-password are rate-limited per IP (see `kk/security.py` and route decorators).
- **Secrets**: Never commit real `SECRET_KEY`, `JWT_SECRET_KEY`, or `MAIL_PASSWORD`; use the host’s environment (e.g. Render Environment tab).

## Optional

- **Redis** (`REDIS_URL`): Improves rate limiting and Socket.IO across workers.
- **Sentry** (`SENTRY_DSN`): Error tracking in production.
- **R2 / S3**: For presigned image uploads; see `.env.example`.

## Quick check

1. Set `APP_ENV=production` and all required env vars.
2. **For password reset emails:** In Render → your service → Environment, add `MAIL_USERNAME` and `MAIL_PASSWORD` (for Gmail use an [App Password](https://support.google.com/accounts/answer/185833)). Redeploy. Logs will show "Password reset email is configured" at startup if set.
3. Deploy; confirm health/root endpoint returns 200.
4. Test signup → login → forgot-password with a **real email** (the account must have an email, not just phone). Check inbox and spam for the reset code.
