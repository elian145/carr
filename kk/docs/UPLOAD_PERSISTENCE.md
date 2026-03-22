# Persisting uploaded photos and videos

## Cloudflare R2 (object storage)

If **`R2_ACCOUNT_ID`**, **`R2_BUCKET_NAME`**, API keys, and **`R2_PUBLIC_URL`** are set, **new videos** uploaded with `POST /api/cars/<id>/videos` are stored in **R2** (key prefix `car_videos/`) and the database stores a full **HTTPS** URL. No Render disk is required for those uploads.

- **`R2_PUBLIC_URL`**: public base for your bucket, e.g. `https://pub-xxxxx.r2.dev` or your **Custom Domain** in Cloudflare.
- Run **`flask db upgrade`** (or your migration command) so `car_video.video_url` is wide enough for long URLs.
- Optional presigned uploads: `POST /api/media/r2/sign-upload` with JSON `"asset": "video"` for direct client → R2 PUT.

---

Listing images and videos can also be saved as **local files** under **`UPLOAD_FOLDER`** (default: `kk/static/uploads/`).

On **Docker**, **Render**, **Heroku**, **Fly.io**, and many other hosts, the filesystem is **ephemeral**: every deploy or container restart can wipe files. The **database** still has rows with `image_url` / `video_url`, so the app shows listings—but requests to `/static/uploads/...` return **HTTP 404** because the files are gone.

## Fix

1. Attach a **persistent disk** or volume to your service.
2. Set an environment variable so uploads go to that disk:

```bash
UPLOAD_FOLDER=/data/uploads
```

3. Ensure the directory exists and is writable (your process should create `car_photos`, `car_videos`, `profile_pictures` under it on startup).
4. **Redeploy** with this env var set.

Existing uploads that were already lost cannot be recovered; re-upload or restore from backup. New uploads will persist as long as the volume is mounted.

## Render (Web Service)

Render’s filesystem is **ephemeral** unless you add a **persistent disk**. Without it, uploads vanish on each deploy/restart → **HTTP 404** for `/static/uploads/...`.

### Steps

1. **Dashboard** → your **Web Service** → **Disks** (sidebar).
2. **Add disk**
   - **Name:** e.g. `uploads-data`
   - **Mount path:** use something stable, e.g. `/data` (Render requires an absolute path; this is a common choice).
   - **Size:** pick enough for photos/videos (e.g. 5–20 GB); you can increase later on paid plans.
3. **Environment** → add:
   ```bash
   UPLOAD_FOLDER=/data/uploads
   ```
   The app creates `car_photos`, `car_videos`, and `profile_pictures` under that path on startup.
4. **Save** and **redeploy** the service so the new disk and env apply.

### Notes

- **One disk per service** — the Web Service that runs Flask must be the one with the disk; workers should read the same URLs over HTTP or share storage another way.
- **Single instance** recommended for this disk model: multiple instances don’t share one disk; for horizontal scaling you’d use **object storage** (e.g. S3/R2) instead of local files.
- **Free / starter** plans may not include persistent disks; check [Render disks](https://render.com/docs/disks).
- Files already lost before adding the disk **cannot** be recovered from Render; re-upload or restore from backup.

## Local development

Leave `UPLOAD_FOLDER` unset to use `kk/static/uploads/` inside the repo (normal for dev).
