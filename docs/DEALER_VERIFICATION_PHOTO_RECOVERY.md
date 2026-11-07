# Dealer verification photos: legacy-photo recovery (read-only investigation + operator steps)

Before this change, verification photos were stored on the web service's ephemeral
local disk and were probably lost at every deploy. After this change new uploads go
to the private R2 bucket (see `docs/R2_PRIVATE_BUCKET_LIFECYCLE.md`). A **legacy**
photo is a `dealer_application.verification_photo_filename` value **without** the
`r2:` prefix. Nothing here modifies production data automatically.

## 1. Find affected applications (read-only SQL)

```sql
-- Legacy references by status (does not tell you whether the file still exists)
SELECT status, count(*)
FROM dealer_application
WHERE verification_photo_filename IS NOT NULL
  AND verification_photo_filename NOT LIKE 'r2:%'
GROUP BY status ORDER BY status;

-- The ones an operator must act on: waiting for a decision
SELECT public_id, status, submitted_at, dealership_name
FROM dealer_application
WHERE verification_photo_filename IS NOT NULL
  AND verification_photo_filename NOT LIKE 'r2:%'
  AND status IN ('submitted', 'under_review')
ORDER BY submitted_at;
```

Whether the file still exists is only knowable through the app: open the application in
the admin dashboard. The photo route answers `404 {"code": "photo_missing"}` for a
lost file (never a 500), `503 photo_storage_unavailable` if storage is down (retry).

## 2. Recovery for `submitted` / `under_review` applications (no DB repair)

A lost photo is recovered **by the applicant re-uploading**, using existing, audited
lifecycle transitions only:

1. Admin opens the application. If the photo is `photo_missing`, **do not approve**.
2. Admin requests changes: `POST /api/admin/dealers/<user_public_id>/review` with
   `{"action": "needs_changes", "reason": "Your verification photo was lost; please upload it again."}`
   (works from both `submitted` and `under_review`; the reason is shown to and
   notified to the applicant). `rejected` also works but discards more state.
3. The applicant uploads a new photo (the upload is blocked while the application is
   `submitted`/`under_review`/`approved`, which is why step 2 is needed). The photo now
   goes to private R2 and replaces the dangling reference.
4. Resubmission on a dangling legacy reference is **refused by the API** ("Your
   verification photo is no longer available. Please upload it again."), so a stale
   value can never be resubmitted by accident.
5. The application returns to `submitted`; review it as normal.

Applicants in `draft`, `needs_changes` or `rejected` can simply upload again.

## 3. Applications that were already `approved`

Approved dealers are unaffected (approval does not need the photo afterwards). If a
re-verification is ever required, use the same `needs_changes` path where permitted, or
ask the dealer to re-apply.

## 4. Do not

* Do not rewrite or null the column by hand in production; the path above is
  sufficient and keeps the decision audit trail (`dealer_decision`).
* Do not copy files between disks; there is no persistent disk and the copy-only CLI was
  deliberately not built (it would only help if a persistent disk exists).
* Deploying this change restarts the web service; any legacy file still on its ephemeral
  disk is lost at that point. If a surviving file matters, capture the list in step 1
  and contact those applicants **before** the deploy.
