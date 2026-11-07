# Private R2 bucket (`R2_CHAT_*`): contents, lifecycle and access requirements

The private bucket (`R2_CHAT_BUCKET_NAME`, credentials `R2_CHAT_ACCESS_KEY_ID` /
`R2_CHAT_SECRET_ACCESS_KEY`) is required in production by boot validation
(`kk/config.py`). It holds two kinds of objects with **different** rules:

| Prefix | Content | Served by | Expiry allowed? |
|---|---|---|---|
| `chat_uploads/`, `chat_videos/`, `chat_audio/` | Chat photos, videos, voice notes | Short-lived presigned GET, only after the message-level authorization check (`kk/models.py::_resolve_chat_media_ref`) | **Not by default.** Chat media is retained after account deletion with no stated retention period (see `/privacy`). Do not add an expiry rule without a published retention decision. |
| `dealer_verification/` | Dealer verification photos (private) | **Only** the admin proxy `GET /api/admin/dealers/<id>/verification-photo` (admin + `dealers` permission) | **Never.** An expiring photo silently breaks a pending application. |

## Required production configuration (owner, Cloudflare dashboard)

Verify each item read-only; change nothing without approval.

1. **No public access.** The bucket has **no** custom domain, **no** `r2.dev`
   public development URL, and no public-read policy. `R2_PUBLIC_URL` belongs to the
   *listing* bucket only; it must never point at this bucket.
2. **Scoped token.** `R2_CHAT_*` credentials are an R2 API token limited to this one
   bucket (object read/write/delete). The listing-bucket token must not be able to
   read this bucket (and vice versa).
3. **Lifecycle rules.** There must be **no** lifecycle rule that expires or
   transitions objects under `dealer_verification/` (or bucket-wide with no prefix
   filter). If any chat-media cleanup rule exists or is ever proposed:
   * scope it with an explicit prefix filter (`chat_uploads/`, `chat_videos/`,
     `chat_audio/`), never bucket-wide;
   * get the retention decision approved and `/privacy` + `/delete-account` updated
     first (they currently state chat media is kept with no fixed period);
   * keep the abort-incomplete-multipart rule (harmless) if present.
4. **No object versioning surprises.** If versioning is on, deletion of a verification
   photo on account deletion leaves a delete-marker; confirm noncurrent versions are
   expired by a rule that **is** prefix-scoped to `dealer_verification/` only if the
   privacy position requires physical erasure (decision for the owner; not enabled
   by this change).
5. **Backups.** The bucket is not covered by the Postgres backup. Dealer
   verification photos are evidence for pending applications; decide whether R2
   object versioning/replication is wanted (owner decision).

## What the code guarantees (and tests pin)

* Verification photos are written only to the private bucket under
  `dealer_verification/` (`kk/private_media.py`); production never falls back to local
  disk.
* The stale-object sweeps (`r2_cleanup_stale_staging`, Celery
  `cleanup_stale_*_staging_objects`) use the **listing** bucket credentials and only
  the `car_photos/_staging/`, `car_videos/_staging/`, `car_videos/_processed_staging/`
  prefixes. No code path lists or bulk-deletes the private bucket.
* `r2_presign_get` refuses `dealer_verification/` keys (and `r2:` references), so a
  chat message can never be used to mint a presigned URL for a verification photo.
  No chat endpoint accepts a client-supplied key.
* Deleting an account or replacing a photo deletes the object (best effort; failures
  are logged, not raised).

## Read-only verification checklist

```text
Cloudflare dashboard -> R2 -> <chat bucket>
  Settings -> Public access: "Disallowed"; no custom domains; r2.dev subdomain disabled
  Settings -> Object lifecycle rules: none, or only prefix-scoped chat_* rules
Cloudflare dashboard -> R2 -> Manage API tokens: chat token scoped to this bucket only
```

Application-side (read-only): `/health` reports `upload_persistence: r2`; the admin
photo route returns `200` with `Cache-Control: no-store, private` and no `Location`.
