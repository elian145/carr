# Persisting uploaded photos and videos

On **Docker**, **Render**, **Heroku**, **Fly.io**, and many other hosts, the container filesystem is **ephemeral**: every deploy or restart can wipe local files. The **database** still has rows with `image_url` / `video_url`, so listings appear—but media URLs return **HTTP 404**.

**Production requirement:** the API refuses to start unless uploads will survive redeploys (see `validate_upload_persistence()` in `kk/config.py`). Escape hatch only: `ALLOW_EPHEMERAL_UPLOADS=1` (emergency; not for store launch).

`GET /health` reports `upload_persistence` as one of:

| Value | Meaning |
|-------|---------|
| `r2` | Cloudflare R2 credentials + `R2_PUBLIC_URL` |
| `disk` | Absolute `UPLOAD_FOLDER` (persistent volume) |
| `r2_incomplete` | R2 keys set but `R2_PUBLIC_URL` missing |
| `ephemeral` | Default local path under the container |

Verify: `python scripts/verify_production_host.py --require-upload-persistence`

---

## Option A — Cloudflare R2 (recommended)

If **`R2_ACCOUNT_ID`**, **`R2_BUCKET_NAME`**, API keys, and **`R2_PUBLIC_URL`** are set:

- **Listing photos** (sync + Celery) go to R2 under `car_photos/` and the DB stores a public HTTPS URL.
- **Listing videos** from `POST /api/cars/<id>/videos` go to R2 under `car_videos/`.
- Optional presigned uploads: `POST /api/media/r2/sign-upload` with JSON `"asset": "image"` or `"video"`.

**`R2_PUBLIC_URL`**: public base for your bucket, e.g. `https://pub-xxxxx.r2.dev` or a Cloudflare **Custom Domain**.

R2 put/presign runs via `tools/r2_s3_op.py` in a subprocess so gunicorn **eventlet** workers do not hit boto3/SSL `RecursionError`.

In production, if R2 is configured but upload fails (or `R2_PUBLIC_URL` is missing), the API **does not** silently write to ephemeral local disk.

Run **`flask db upgrade`** so `car_image.image_url` and `car_video.video_url` are wide enough for long R2/CDN URLs.

---

## Option B — Persistent disk (`UPLOAD_FOLDER`)

1. Attach a **persistent disk** or volume to your service.
2. Set:

```bash
UPLOAD_FOLDER=/data/uploads
```

3. Ensure the directory is writable (the process creates `car_photos`, `car_videos`, `profile_pictures` on startup).
4. **Redeploy** with this env var set.

Existing uploads that were already lost cannot be recovered; re-upload or restore from backup.

### Render (Web Service)

1. **Dashboard** → your **Web Service** → **Disks**.
2. **Add disk** — mount path e.g. `/data`, size enough for photos/videos.
3. **Environment** → `UPLOAD_FOLDER=/data/uploads`.
4. Save and redeploy.

**Notes**

- One disk per service; multiple instances do not share one disk—prefer R2 for horizontal scaling.
- Free / starter plans may not include disks; see [Render disks](https://render.com/docs/disks).
- **The async Celery image-processing pipeline requires Option A (R2), not
  Option B, in this app's multi-service deployment.** `POST
  /api/cars/<id>/images?async=1` and `POST
  /api/process-car-images?async=1` enqueue `kk.tasks.image_tasks.
  process_car_image_file` on `carr-worker-fra` -- a *separate* Render
  service from `carr` (the web process that accepted the upload). Render
  never shares a disk across services (see the note above and
  [Render disks](https://render.com/docs/disks)), so a local `UPLOAD_FOLDER`
  path written by `carr` is not readable by `carr-worker-fra`. When R2 is
  configured, the enqueuing route stages the original upload to a
  short-lived `car_photos/_staging/` R2 key instead
  (`kk.media_processing.stage_upload_for_async_job`) and the worker
  downloads it from there; this staging object -- and the worker's own
  downloaded copy -- are removed once the job finishes (success or
  failure), with an hourly Celery Beat sweep
  (`cleanup_stale_image_staging_objects`) as a backstop for a lost/abandoned
  job. If this app is ever deployed with Option B (disk) instead of R2
  *and* a separate Celery worker service, every async image job will fail
  with a missing-source error -- Option B alone only ever worked safely
  because the confirmed-fixed OOM bug (see the production OOM investigation)
  meant this cross-service path was not yet exercised end-to-end in
  production.

---

## Local development

Leave `UPLOAD_FOLDER` unset to use `kk/static/uploads/` inside the repo. Production fail-fast does not apply when `APP_ENV=development` or `testing`.
