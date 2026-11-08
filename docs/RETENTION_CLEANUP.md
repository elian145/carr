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

## `admin_audit_log` and personal data - what is stored, and the open owner decision

Stored per row: the acting admin's numeric id and a **username snapshot** (staff
identity), the action type, the target type/id (for users this is the target's
`public_id`, a pseudonymous identifier), and bounded metadata. Metadata passes
through `kk.auth.audit_safe_metadata`: values under personal-data-looking keys
(email, phone, password, token, address, ...) are redacted, strings are truncated
to 200 characters, containers and the whole document are size-capped, and the
user- and listing-status endpoints log only an allowlist of fields, never the raw
request body. Admin-written free text (e.g. a rejection `reason`) can still
appear, truncated.

The privacy draft's deletion matrix (`docs/PRIVACY_DRAFT_ACCOUNT_DELETION.md`)
does not mention this table, so **keeping these rows after an account is deleted
is not covered by any approved statement**. The table is append-only by design
(a database trigger on PostgreSQL), so erasure is an operator action. Owner to
decide: (a) disclose it in the privacy text with a stated purpose (security /
abuse audit) and a retention period, or (b) approve a documented pseudonymisation
procedure for the target id and admin username on erasure requests. Nothing here
invents either choice.
