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

---

## Local development

Leave `UPLOAD_FOLDER` unset to use `kk/static/uploads/` inside the repo. Production fail-fast does not apply when `APP_ENV=development` or `testing`.
