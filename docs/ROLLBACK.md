# Rollback plan

Use this if a bad mobile or API update goes out after launch. For the forward deploy
order and post-deploy checks see [`RELEASE_DEPLOY_ORDER.md`](RELEASE_DEPLOY_ORDER.md).

## Mobile app (Play / App Store)

1. **Stop the bleeding** — In Play Console / App Store Connect, halt phased rollout or pause the release if still rolling out.
2. **Restore previous store build** — Promote the last known-good production version (Play: “App bundle explorer” → previous release; App Store: select previous build for a new version or use phased rollback if available).
3. **Force users off the bad build** — Set `min_android_build` / `min_ios_build` (or `min_app_version`) via admin Settings / `/api/config/app` so older clients prompt update only when a fixed build is live — do **not** raise the floor while only the bad build is current.
4. **Communicate** — Post a short note on support channels if users already hit a broken flow.

## Backend (Render / API)

1. **Redeploy previous commit** — In Render (or your host), redeploy the last green deploy of `kk.wsgi:app`. Prefer git tag / commit SHA you already tested. **If the database has already been migrated past that commit, read “Database” below first: the previous commit will not start by itself.**
2. **Database** — Do **not** downgrade or restore as a reflex. Read “Database” below and pick the least destructive option that works. Never run destructive SQL against production without a restore point (see `docs/BACKUPS_AND_BILLING.md`).
3. **Feature flags** — Use platform settings / `listing_require_approval` and feature flags to disable sell/chat if needed without a full rollback.
4. **Verify** — Hit `/health`, open one listing, create a test listing, send a chat message.

## Checklist after rollback

- [ ] Store listing shows the restored version
- [ ] Sentry (if configured) shows error rate dropping
- [ ] Support inbox monitored for residual reports
- [ ] Root-cause fix branched from the bad commit; do not hot-patch production blindly

## Database

### Current migration head: `b8e4f2a6c1d3`

`flask db heads` prints exactly one head, `b8e4f2a6c1d3`, and `flask db current` on an
up-to-date database must print `b8e4f2a6c1d3 (head)`. Production's last revision
before this release is **assumed** to be `v0w1x2y3z4a5` — confirm with
`flask db current` against production **before** deploying (`docs/RELEASE_DEPLOY_ORDER.md`,
step 2); if it prints anything else, stop and re-derive the plan below.

Three revisions sit on top of `v0w1x2y3z4a5`, in this order. All three are **purely
additive** (each creates only new objects; no existing table, column or row is touched
and nothing is backfilled), so the previous release never reads them. They are not
reversible without losing data:

| Order | Revision | Adds | What a downgrade of that step destroys |
|---|---|---|---|
| 1 | `f04a1b2c3d4e` | `saved_search_alert_job` (durable saved-search alert jobs) | The table: pending and finished alert-job history, **and** the `UNIQUE(car_id)` first-publication marker (a listing republished later could be alerted again). Listings, saved searches and `saved_search_alert` de-dupe rows are untouched. |
| 2 | `a7d3e1c9b5f2` | `account_deletion_request` (durable web account-deletion requests) | The table: **every request, pending and completed**. A pending row is the only durable copy of the person's request (the support email is only a notification), and completed rows are the record of how each request was resolved. |
| 3 | `b8e4f2a6c1d3` | `admin_audit_log` + PostgreSQL append-only trigger `admin_audit_log_no_update_delete` and function `admin_audit_log_append_only()` | The table, its indexes, the trigger and the function: **the entire administrator audit trail since the release**, including the `retention_run` rows the retention job writes. Once dropped, those rows cannot be reconstructed (`user_action` is untouched but is a different, cascade-deleted history). |

> `start_render.sh` runs `python -m flask db upgrade` (with `set -e`) on **every** `carr`
> start. This has two consequences that drive every option below:
>
> 1. Starting the **new** code again after a downgrade silently **re-applies** the
>    migrations (empty tables, lost rows stay lost).
> 2. Starting **older** code against a database stamped with a revision it does not
>    contain **fails**: Alembic exits 1 with `Can't locate revision identified by
>    'b8e4f2a6c1d3'` and the service never reaches Gunicorn. (Reproduced locally by
>    stamping a database with an unknown revision and running `flask db upgrade`.)

### Hazards (read before choosing an option)

- **Downgrades are data loss.** Each downgrade step in the table above permanently deletes rows.
  There is no downgrade that is both complete and lossless.
- **Do not assume `v0w1x2y3z4a5` is the right target.** Downgrading to `v0w1x2y3z4a5`
  removes all three tables. Use it only if a schema-level rollback is truly required (a
  migration itself is faulty) and only after the exports below. A code-only rollback
  (Option 1) normally does not need any downgrade.
- **Partial downgrades need matching code.** If you stop at `f04a1b2c3d4e` or
  `a7d3e1c9b5f2`, the code you redeploy must have exactly that revision as its Alembic head
  (check out the commit and run `flask db heads`). Any newer code re-applies the dropped
  migrations on start, and any older code refuses to start (consequence 2 above).
- **Retention deletions are irreversible.** `RETENTION_ENABLED` is off by default
  (`docs/RETENTION_CLEANUP.md`). If you enabled it with `RETENTION_DRY_RUN=0`, rows it
  already deleted exist only in backups, regardless of which option you pick.
- **Restoring a backup discards every later write** (users, listings, chat messages,
  deletion requests) and does not roll back Cloudflare R2 objects.
- **The audit trail is append-only by design.** On PostgreSQL the trigger rejects
  `UPDATE` and `DELETE` on `admin_audit_log`; you cannot “fix” or prune rows with SQL
  while the trigger exists, and you should not drop the trigger to work around a rollback.

### Required before ANY rollback step that touches the schema or restores data

Do these first, in this order. They are read-only on the source database. Run them from
a trusted workstation with the production `DATABASE_URL` held only in your shell
environment (never commit or paste it).

1. **Stop writers.** Suspend `carr-beat-fra` first (so no retention or notification job
   fires mid-rollback), then `carr-worker-fra`, then `carr`. Auto-deploy is already `off`,
   so nothing restarts on its own.
2. **Take a fresh logical backup of the whole database** and confirm it is readable
   (restore it into a scratch database, or at minimum `pg_restore --list` it). Also
   confirm the Render Postgres backup / point-in-time-recovery window in the dashboard
   (`docs/BACKUPS_AND_BILLING.md`). A full backup is not a substitute for step 3.
3. **Export the three tables separately**, so the data can be re-imported after the new
   code is re-deployed (the schema upgrade recreates the tables empty):

   ```bash
   pg_dump "$DATABASE_URL" --data-only --format=custom \
     --table=public.saved_search_alert_job \
     --table=public.account_deletion_request \
     --table=public.admin_audit_log \
     --file=rollback_additive_tables.dump
   ```

   and, for human review, one CSV each. Compare each file's row count with the live
   count before you continue:

   ```sql
   SELECT count(*) FROM saved_search_alert_job;
   SELECT count(*) FROM account_deletion_request;            -- all statuses
   SELECT count(*) FROM account_deletion_request WHERE status = 'pending';
   SELECT count(*) FROM admin_audit_log;
   \copy (SELECT * FROM saved_search_alert_job ORDER BY id) TO 'saved_search_alert_job.csv' CSV HEADER
   \copy (SELECT * FROM account_deletion_request ORDER BY created_at) TO 'account_deletion_request.csv' CSV HEADER
   \copy (SELECT * FROM admin_audit_log ORDER BY id) TO 'admin_audit_log.csv' CSV HEADER
   ```

   These files contain personal data (phone numbers, emails, free-text details, hashed IPs,
   admin usernames and action metadata): store them encrypted, restrict access, and
   securely delete them when no longer needed. **Pending deletion requests are legally
   significant:** process every `pending` row manually (delete the account or answer the
   person) before or immediately after the rollback, and do not delete the export until
   that is done.

### Option 1 (preferred): roll back the code only, keep the schema at `b8e4f2a6c1d3`

No data is lost, because the three tables are additive and the older release never reads
or writes them. Use this unless a migration itself is the problem.

1. Suspend `carr-beat-fra` and `carr-worker-fra` (leave `carr` for step 3). Take the full
   backup from the section above (step 2); the per-table exports are optional here
   because nothing is dropped, but still process any pending deletion requests.
2. In the Render dashboard, **override the `carr` Start Command** for the rollback deploy to
   `gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"` (the other start command `DEPLOYMENT.md`
   allows). This skips the `flask db upgrade` that would otherwise abort on the unknown
   revision. Leave the database stamped `b8e4f2a6c1d3`.
3. Manually deploy the previous commit to `carr`; then to the worker and beat services
   that need it. Confirm `/health`.
4. Consequences while the old code is live: the public `/delete-account` form is
   **email-only** again (new requests are not recorded in `account_deletion_request`;
   rows already there are not shown anywhere, so process them from the export); administrator
   actions are **not** written to `admin_audit_log` (only to `user_action`); retention and
   durable saved-search alert jobs do not run.
5. **Restore the normal Start Command** (`bash start_render.sh`) before the next forward
   deploy, otherwise migrations will not run. Re-deploying the fixed new code later needs no
   re-import: the tables and their rows are still there.

> This path has been reasoned from the migrations (each states the previous release keeps
> working) and the `start_render.sh` behaviour above, but it has **not** been rehearsed
> against a production-sized copy. Rehearse it on a restored backup if time allows.

### Option 2: downgrade the schema (data loss — only if required)

Only if the schema itself must change. Complete “Required before ANY rollback” first,
**including the per-table exports**, and decide how far to go:

```bash
export FLASK_APP=kk.wsgi:app
flask db current                    # confirm b8e4f2a6c1d3 before starting

flask db downgrade a7d3e1c9b5f2     # drops admin_audit_log (+ trigger/function); audit rows lost
flask db downgrade f04a1b2c3d4e     # drops account_deletion_request; ALL requests lost
flask db downgrade v0w1x2y3z4a5     # drops saved_search_alert_job; production's assumed previous head
flask db current                    # must print the revision you intended to stop at
```

Stop at the **first** line that solves the problem; do not run the later lines by habit.
Then deploy a commit whose Alembic head is exactly the revision you stopped at, using the
normal Start Command only if that commit's head matches (otherwise use the Start Command
override from Option 1). Listings, users, dealer applications, chat and every other table
are untouched by these downgrades.

To bring the data back after re-deploying the new code: let `flask db upgrade` recreate
the tables, then restore each dump with `pg_restore --data-only` (or `\copy ... FROM`).
`INSERT` is allowed by the append-only trigger, so `admin_audit_log` can be restored;
`id` values are preserved by the dump, so reset the sequences afterwards
(`SELECT setval(pg_get_serial_sequence('<table>','id'), max(id)) FROM <table>`).

Re-submit anything the public form answered with 503 during the window (the API never
reported success for those).

### Option 3 (last resort): restore from backup / point-in-time recovery

Only if data itself is corrupted. Restore into a **new** Postgres instance, never over the
live database, then point `DATABASE_URL` on `carr` and `carr-worker-fra` at it. Everything
written after the restore point is lost and must be reconciled by hand (new users,
listings, chat messages, deletion requests, audit rows). R2 objects are not rolled back,
so some objects may no longer be referenced. Decide the Start Command as in Options 1/2
according to the revision the restored database carries (`flask db current`).

### Dealer verification photos are not part of the schema rollback

Photo references live in the existing `dealer_application.verification_photo_filename`
column, so the migrations above neither create nor remove them. Objects in the private R2
bucket (`dealer_verification/`) survive a code rollback, but old code cannot read an
`r2:` reference (it would look for a local file named `r2:...`): applicants uploaded
after the release candidate must re-upload if you roll back. See
`docs/DEALER_VERIFICATION_PHOTO_RECOVERY.md` and `docs/R2_PRIVATE_BUCKET_LIFECYCLE.md`.
