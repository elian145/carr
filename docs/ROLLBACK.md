# Rollback plan

Use this if a bad mobile or API update goes out after launch.

## Mobile app (Play / App Store)

1. **Stop the bleeding** — In Play Console / App Store Connect, halt phased rollout or pause the release if still rolling out.
2. **Restore previous store build** — Promote the last known-good production version (Play: “App bundle explorer” → previous release; App Store: select previous build for a new version or use phased rollback if available).
3. **Force users off the bad build** — Set `min_android_build` / `min_ios_build` (or `min_app_version`) via admin Settings / `/api/config/app` so older clients prompt update only when a fixed build is live — do **not** raise the floor while only the bad build is current.
4. **Communicate** — Post a short note on support channels if users already hit a broken flow.

## Backend (Render / API)

1. **Redeploy previous commit** — In Render (or your host), redeploy the last green deploy of `kk.wsgi:app`. Prefer git tag / commit SHA you already tested.
2. **Database** — Prefer forward-fix migrations. If a migration must be undone, restore from the latest Postgres backup/PITR first (see `docs/BACKUPS_AND_BILLING.md`), then redeploy matching code. Never run destructive SQL against production without a restore point.
3. **Feature flags** — Use platform settings / `listing_require_approval` and feature flags to disable sell/chat if needed without a full rollback.
4. **Verify** — Hit `/health`, open one listing, create a test listing, send a chat message.

## Checklist after rollback

- [ ] Store listing shows the restored version
- [ ] Sentry (if configured) shows error rate dropping
- [ ] Support inbox monitored for residual reports
- [ ] Root-cause fix branched from the bad commit; do not hot-patch production blindly


## Database head `a7d3e1c9b5f2` (release candidate: PR #36 + Batch 8)

Alembic chain added on top of production's current head `v0w1x2y3z4a5`
(`listing_moderation_*`), both **purely additive** (new tables only, no existing
table/column/row touched, nothing backfilled):

| Revision | Adds | Downgrade effect |
|---|---|---|
| `f04a1b2c3d4e` | `saved_search_alert_job` (F-04 durable alert jobs) | drops the table (job history only) |
| `a7d3e1c9b5f2` | `account_deletion_request` (durable web deletion requests) | drops the table **including any pending requests** |

`flask db current` on a release-candidate database must print `a7d3e1c9b5f2 (head)`;
`flask db heads` must list exactly one head.

### Forward deploy

`start_render.sh` runs `flask db upgrade` on every `carr` start, so the deploy applies
both migrations. They take only a brief lock (`SET LOCAL lock_timeout = '5s'` on the
FK to `car` / `user`); if the lock is not obtained the migration fails, the deploy
stops and the running release keeps serving. Take a backup/restore point first
(`docs/BACKUPS_AND_BILLING.md`).

### Rolling back to code that predates these revisions

Old code **fails** against a database stamped with an unknown revision, and a restart of
the new code **re-applies** the migrations, so the order matters:

1. Suspend `carr` (and `carr-worker-fra` / `carr-beat-fra`) in Render so nothing restarts
   mid-rollback. Auto-deploy is already `off`.
2. **Preserve pending deletion requests** (they are the only copy; the email is only a
   notification). From a trusted workstation, read-only on the source:

   ```sql
   -- row count to compare after export
   SELECT count(*) FROM account_deletion_request WHERE status = 'pending';
   \copy (SELECT public_id, phone, email, details, created_at, notified_at, last_notify_error FROM account_deletion_request WHERE status = 'pending' ORDER BY created_at) TO 'pending_deletion_requests.csv' CSV HEADER
   ```

   The file contains personal data: store it encrypted, restrict access, process every
   row manually (delete the account, answer the person), then securely delete it. Do
   **not** downgrade until the row count in the file matches.
3. Downgrade the database first (one step at a time is fine):

   ```bash
   flask db downgrade f04a1b2c3d4e   # drops account_deletion_request only
   flask db downgrade v0w1x2y3z4a5   # drops saved_search_alert_job; production's previous head
   flask db current                   # must print v0w1x2y3z4a5
   ```

   Listings, users, dealer applications, chat and every other table are untouched.
4. Redeploy the previous commit (`docs/ROLLBACK.md` -> Backend). The old web form
   goes back to **email-only** delivery: tell support that web deletion requests are
   again not durably recorded, and keep the exported file as the source of truth for
   anything received before the rollback.
5. Re-submit anything the public form answered with 503 during the window (the API never
   reported success for those).

### Partial rollback (keep F-04, revert only deletion requests)

Redeploy the commit that has `f04a1b2c3d4e` as head **after** running
`flask db downgrade f04a1b2c3d4e` (steps 1-2 above still apply). Code that expects
`account_deletion_request` against a downgraded database answers the public form with
503 ("could not record your request") and the admin queue with an error, never with a
false success.

### Dealer verification photos are not part of the schema rollback

Photo references live in the existing `dealer_application.verification_photo_filename`
column, so the migrations above neither create nor remove them. Objects in the private R2
bucket (`dealer_verification/`) survive a code rollback, but old code cannot read an
`r2:` reference (it would look for a local file named `r2:...`): applicants uploaded
after the release candidate must re-upload if you roll back. See
`docs/DEALER_VERIFICATION_PHOTO_RECOVERY.md` and `docs/R2_PRIVATE_BUCKET_LIFECYCLE.md`.
