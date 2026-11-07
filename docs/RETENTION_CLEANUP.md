# Retention cleanup (audit F-16) and admin audit trail (F-17)

## What is implemented

`kk/retention.py`, run daily by Celery beat (`retention-cleanup`,
`kk/tasks/retention_tasks.py`). **Every job is a no-op until its env var is set**;
no retention period is built in or assumed.

| Env var | Effect when set |
|---|---|
| `RETENTION_TOKEN_BLACKLIST_PURGE=1` | Delete `token_blacklist` rows whose JWT expired > 1 h ago (already dead; behaviour-neutral). |
| `RETENTION_USER_ACTION_DAYS=<n>` | Delete `user_action` analytics rows older than *n* days. `admin_*` actions are never deleted. |
| `RETENTION_READ_NOTIFICATION_DAYS=<n>` | Delete **read** notifications older than *n* days. Unread are never deleted. |

Deletes run in batches of 1000 (max 100 batches per table per run).

## Never touched by the job

`admin_audit_log` (append-only; no FK to `user`, so user/listing deletes cannot
cascade into it; PostgreSQL trigger rejects UPDATE/DELETE), chat messages and chat
media (privacy policy: no automatic expiry, no stated period), reports, listings, users.

## Owner decisions required (not made here)

1. Retention period for `user_action` (analytics: views, logins) and whether the
   privacy policy should state it.
2. Period for read notifications (and whether unread ones should ever expire).
3. Whether to enable `RETENTION_TOKEN_BLACKLIST_PURGE` now (recommended; safe).
4. Any retention for `admin_audit_log` (none implemented; append-only by design).
5. Chat messages/media expiry remains a published-policy decision
   (see `docs/PRIVACY_DRAFT_ACCOUNT_DELETION.md`).
6. Index on `user_action.user_id` (not added: building it on a large live table
   needs `CREATE INDEX CONCURRENTLY` in a maintenance window).
7. One-click "hide listing / suspend user" from a report (F-18 second half) is a
   product decision; reports are still resolved manually.

Requires a Celery **beat** process to be running (see `render.yaml` carr-beat).
