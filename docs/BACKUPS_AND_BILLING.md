# Backups & billing alerts (operator setup)

These cannot be enabled from app code alone. Complete before launch.

## Database backups

**Render Postgres (typical for this project):**

1. Open the Render dashboard → your Postgres instance.
2. Enable **automatic backups** / point-in-time recovery (plan-dependent).
3. Confirm retention (recommend ≥7 days).
4. Once: practice restoring a backup into a staging DB.

**If self-hosted:** schedule `pg_dump` daily to object storage; test restore monthly.

Document the restore steps next to your host login (or link from `DEPLOYMENT.md`).

## Billing alerts / budgets

Set budget alerts on every pay-as-you-go account:

| Service | Why |
|---------|-----|
| Render (hosting + Postgres + Redis + disk) | Traffic / disk spikes |
| OpenAI (if `OPENAI_API_KEY` set) | Spec suggestion / AI routes |
| Google Cloud (Maps, Places, Firebase) | Maps + FCM misuse if keys leak |
| SMS provider (OTPIQ / etc.) | OTP abuse |
| Email (Resend / SendGrid) | Verification / deletion mail |

Create an alert at a low threshold (e.g. $50–100) and a hard cap if the vendor supports it.

Also restrict API keys per `docs/FIREBASE_API_KEYS.md`.
