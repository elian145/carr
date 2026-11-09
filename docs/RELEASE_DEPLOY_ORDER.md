# Release deploy order and post-deploy checks

Applies to the Render blueprint in [`render.yaml`](../render.yaml): `carr` (API),
`carr-worker-fra` (Celery worker), `carr-beat-fra` (Celery beat) and `carr-admin`
(admin-web). Every service has `autoDeployTrigger: 'off'`, so each step below is a
**manual deploy** in the Render dashboard. Rollback: [`ROLLBACK.md`](ROLLBACK.md).

This document describes steps the owner performs. Nothing here is run by CI, and no
command below should be pasted with a production secret on the command line: hold
`DATABASE_URL` and similar values only in your shell environment, or use the Render
**Shell** of the `carr` service, which already has them.

## Commands as defined in the repository (verified)

| Service | Build | Start | Health check |
|---|---|---|---|
| `carr` | `pip install --upgrade pip setuptools wheel` then `pip install --no-cache-dir -r kk/requirements.txt` | `bash start_render.sh` = `python -m flask db upgrade` (with `set -e`, `FLASK_APP=kk.wsgi:app`) then `exec gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"` | `/health` |
| `carr-worker-fra` | as `carr`, plus an ffmpeg/ffprobe prefetch that fails the build if either binary is missing | `celery -A kk.tasks.celery_app.celery_app worker --loglevel=info --concurrency=1 --max-tasks-per-child=50 --max-memory-per-child=200000` | none (background worker) |
| `carr-beat-fra` | as `carr` | `celery -A kk.tasks.celery_app.celery_app beat --loglevel=info` | none (background worker) |
| `carr-admin` | `npm ci && npm run build` (Node 22) | `npm start` | `/api/health` |

- `gunicorn.conf.py` runs one `gthread` worker (`workers=1`, `GUNICORN_THREADS` default 32) —
  keep it that way for Socket.IO (`DEPLOYMENT.md`, “Socket.IO scaling”).
- Only `carr` runs migrations. Worker, beat and admin never do.
- The Procfile's worker line uses `--concurrency=2`; Render uses the `render.yaml` value `1`.

## Environment each service needs

All values are dashboard-managed (`sync: false` in `render.yaml`; a Blueprint sync does not
overwrite a value that is already set and no value is stored in Git).

| Variable | `carr` | `carr-worker-fra` | `carr-beat-fra` | Notes |
|---|---|---|---|---|
| `APP_ENV` | `production` | `production` (literal in `render.yaml`) | `production` (literal) | |
| `SECRET_KEY`, `JWT_SECRET_KEY` | required | required (same values as `carr`) | – | Boot fails if unset or the dev fallback |
| `DATABASE_URL` | required | required (same database) | – | |
| `SUPPORT_EMAIL` | required | required | – | Boot fails if unset: workers too (every task builds the app) |
| `REDIS_URL` | required | required | required | Same Redis; PINGed at boot on `carr`/worker; Frankfurt internal URL |
| `R2_ACCOUNT_ID`, `R2_BUCKET_NAME`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PUBLIC_URL` | required | required | – | Listing media persistence |
| `R2_CHAT_BUCKET_NAME`, `R2_CHAT_ACCESS_KEY_ID`, `R2_CHAT_SECRET_ACCESS_KEY` | required | required | – | All three together, private bucket |
| `FIREBASE_SERVICE_ACCOUNT_BASE64`, `FIREBASE_EXPECTED_PROJECT_ID` | needed for push | needed for push | – | Not boot-required; push is disabled when unset |
| `ANDROID_SHA256_CERT_FINGERPRINTS`, `APPLE_TEAM_ID` | needed for App/Universal Links | – | – | See `docs/ANDROID_APP_LINKS_SETUP.md` |
| `ADMIN_JWT_*` | per `docs/F19_ADMIN_TOKEN_SEPARATION.md` | – | – | |

`carr-beat-fra` never builds the Flask app (verified: importing `kk.tasks.celery_app` with only
`APP_ENV` and `REDIS_URL` succeeds), so it needs only those two.

`carr`, `carr-worker-fra` and `carr-beat-fra` must be in the **same Render region as the
Redis instance** (Frankfurt). The blueprint pins the worker and beat to `frankfurt`; `carr`
has no `region` in the blueprint, so confirm it in the dashboard.

## Order

1. **Pre-flight (nothing deployed yet).**
   - The commit to deploy is the green one (all CI jobs). Note its full SHA; deploy that SHA only.
   - Every variable in the table above is present on the right service (dashboard
     **Environment** tab). Compare names only; do not copy values into chat or tickets.
   - Take the database backup described in [`ROLLBACK.md`](ROLLBACK.md) and confirm the Postgres
     backup / PITR window in the dashboard.
2. **Check the database revision before migrating** (read-only). In the `carr` Shell:

   ```bash
   FLASK_APP=kk.wsgi:app python -m flask db current
   ```

   Expected before this release: `v0w1x2y3z4a5` (assumed — verify). If it prints anything
   else, stop and re-derive the migration/rollback plan; do not deploy. The new head is
   `b8e4f2a6c1d3`, reached via `f04a1b2c3d4e` -> `a7d3e1c9b5f2` -> `b8e4f2a6c1d3`.
3. **Deploy `carr` first.** Its start command applies the migrations before Gunicorn starts. The
   three migrations are additive; the two with a foreign key use `SET LOCAL lock_timeout =
   '5s'`, so a lock conflict makes the migration (and the deploy) fail while the previous
   instance keeps serving. In the deploy log expect `Running upgrade ... -> b8e4f2a6c1d3`,
   then `Starting gunicorn...`. A failed deploy that never turns healthy leaves production
   on the old release; read the log before retrying.
4. **Run the API checks below** and do not continue until they pass.
5. **Deploy `carr-worker-fra`.** It runs the new task code against the already-migrated
   database. Deploying it before step 3 would run new tasks against missing tables.
6. **Deploy `carr-beat-fra` after the worker is healthy.** Beat enqueues tasks (including
   `retention-cleanup`, which stays inert while `RETENTION_ENABLED` is unset); an old worker
   would not know them. Keep exactly **one** beat instance: two schedulers double-enqueue.
7. **Deploy `carr-admin` last of the web services**, after the API it proxies is healthy
   (`NEXT_PUBLIC_API_BASE` is baked in at build time; if the API host changes, rebuild).
8. **Mobile builds / store submission** go after the backend is verified; a new client must
   never reach an API that does not yet have its endpoints.

Leave the opt-in switches at their defaults for this release (`RETENTION_ENABLED` unset,
`SAVED_SEARCH_ALERT_DURABILITY` default `off`); enable them later as separate, deliberate steps.

## Post-deploy checks

**After `carr` (step 4):**

- Deploy log contains no `Missing required environment variables` and no Alembic error.
- `https://<api-host>/health` returns `200` with `"status":"ok"`, and in production also
  `"redis_configured": true`, `"upload_persistence"` showing R2, and the app-links flags you expect.
- `FLASK_APP=kk.wsgi:app python -m flask db current` prints `b8e4f2a6c1d3 (head)`; `flask db heads`
  prints exactly one head.
- From a trusted workstation:

  ```bash
  python scripts/verify_production_host.py --host https://<api-host> --require-app-links --require-upload-persistence
  ```

- `https://<api-host>/health/push` reports `fcm_ready: true` (needs `FIREBASE_SERVICE_ACCOUNT_BASE64`).
- Sign in on a test account, open a listing, create/edit a test listing, send a chat message
  (text, and one image to exercise the private chat bucket), and confirm a Socket.IO connection.
- Submit the public `/delete-account` form with an obviously fake phone number, confirm the row
  appears in the admin deletion-request queue, then complete it as `no_account_found`.
- Perform one harmless admin action, then confirm the append-only trail is being written
  (read-only query; the admin UI “Audit log” page is backed by `user_action`, not this table):

  ```sql
  SELECT count(*), max(created_at) FROM admin_audit_log;
  ```

**After `carr-worker-fra` (step 5):**

- Log shows the worker connected to Redis and `ready`, with no boot error (a missing
  `SUPPORT_EMAIL` or R2 variable exits immediately).
- Upload a test image/video through the API and confirm the media task finishes.

**After `carr-beat-fra` (step 6):**

- Log shows beat started and periodically sending tasks (for example
  `process-due-scheduled-notifications`); the worker log shows them received and succeeded.
- Exactly one beat instance is running; the old Oregon `carr-worker` / `carr-beat` services,
  if they still exist in the dashboard, are deleted.

**After `carr-admin` (step 7):**

- `https://<admin-host>/api/health` returns `200`; sign in through the browser; verify the
  deletion-request queue and one settings page load.

**If any check fails:** stop, do not proceed to the next service, and follow
[`ROLLBACK.md`](ROLLBACK.md). If the database has been migrated, remember that the previous
release will not start with the default start command (see “Option 1” there).
