# Listing edit moderation: release, rollback, limitations

Edits to an **Active** listing are saved to a hidden working copy
(`car.status='revision'`, `is_active=false`) linked by a `car_revision` row.
The public listing changes only when an admin approves. See
`kk/listing_revisions.py` for the design.

## Two-stage release (never skip stage 1)

| Stage | Commit | What it contains |
|---|---|---|
| 0 | `07a52d2` | production today (Alembic head `t8u9v0w1x2y3`) |
| 1 "bridge" | `release/listing-edits-bridge` | production code + migration `u9v0w1x2y3z4` (creates `car_revision`) + a schema-drift whitelist. **No application change.** |
| 2 "feature" | `release/listing-edits-feature` | the feature (backend, worker, beat, admin-web) |

1. Deploy the **bridge** (backend; `start_render.sh` runs `flask db upgrade`).
   Run the upgrade from one instance (two simultaneous upgrades race on
   `CREATE TABLE`; the loser exits non-zero and simply succeeds on restart).
2. Verify: the service is healthy, `alembic_version` is `u9v0w1x2y3z4`.
3. Deploy the **feature** to backend, **worker and beat** (new beat entry
   `sweep-idle-listing-revisions`) and admin-web.
4. Release the Flutter build only after step 3 is healthy.

## Rollback

* **The rollback target is the bridge, never `07a52d2`.** Code that does not
  know head `u9v0w1x2y3z4` cannot start (`flask db upgrade` fails with
  "Can't locate revision"), so it would take the service down.
* **Do not delete pending edits.** Never run
  `DELETE FROM car WHERE status='revision'`: those rows are sellers' unsent
  work. Nothing needs to be deleted to roll back; the bridge boots on a
  database that contains pending edits and ignores them.
* Do not run `flask db downgrade`: it drops `car_revision` (and with it the
  link to every pending edit).
* Rolling forward again restores everything: pending edits, their photos and
  the review queue are intact.

### What the bridge does while pending edits exist (verified on PostgreSQL 17)

Safe:
* Approved listings are served exactly as before: detail, search (including
  Postgres full-text), lists, counts, My Listings, favourites. The working
  copies never appear, because they are inactive with a non-public status.
* Nothing publishes a pending edit: the bridge has no code that reads
  `car_revision` or copies a working copy onto a listing.

Limitations while the bridge is running (temporary, no data is lost):
1. **No moderation of seller edits.** The old code applies a seller's edit to
   the live listing immediately, exactly as before the feature. Pending edits
   stay stored but cannot be reviewed (the admin "Listing edits" API does not
   exist on the bridge; the page shows an error).
2. **Do not touch `status='revision'` rows in the old admin Listings page.**
   They are visible (and counted in admin totals) there. Activating,
   unhiding, deleting or purging one would publish or destroy a seller's
   unsent edit. Ignore them.
3. **Deleting a listing that has a pending edit.** An owner delete is a soft
   delete (the row is kept, inactive): the pending edit stays linked but
   inert (the review queue and approval ignore inactive listings). A hard
   delete (admin purge) removes the revision link and leaves the working copy
   behind as an inert, invisible orphan row. After rolling forward, orphans
   (and only orphans) can be removed:
   ```sql
   DELETE FROM car
   WHERE status = 'revision'
     AND id NOT IN (SELECT shadow_car_id FROM car_revision);
   ```
4. **Stale pending edits after roll-forward.** An edit made before the
   rollback may predate changes the seller made directly while on the bridge.
   Approving it replaces the live fields with the older proposal. After rolling
   forward, review the queue (the page shows approved vs proposed) and reject
   anything that is now stale; the seller keeps the live listing and can
   resubmit.
5. Old-app drafts (`editing_legacy`) are not auto-submitted while on the bridge
   (the sweeper runs only in the feature build); they resume afterwards.
6. Account deletion on the bridge scrubs and hides the user's rows, including
   working copies. That is the existing deletion behaviour and the listing is
   already gone from the public.

## Seller drafts and old app versions

* A review-aware app build sends `X-Carnet-Review-Aware: 1` on every request.
  Its drafts are state `editing`. **They are never submitted automatically**:
  only the seller submits (an explicit Save) or discards them.
* A build without that header (every build released before this feature) cannot
  send the final submit call after changing photos. Such drafts are created as
  `editing_legacy`, and are the only drafts the sweeper (every 15 min, after 30
  min idle) finalizes:
  * nothing differs from the live listing: the draft is discarded;
  * differs **and** is complete (every declared photo/video attached, none
    failed or in flight, cover present): submitted for admin review, i.e.
    set to `pending`. It cannot publish anything: only an admin approval does;
  * otherwise (failed or unfinished uploads): left exactly as is, never
    submitted, never deleted.
* Any request carrying the header turns an `editing_legacy` draft into a normal
  `editing` draft (sticky towards "seller decides").
* A rejected edit that is touched again becomes `editing`, never auto-submitted.
* A pending edit with a failed photo cannot be approved (`media_failed`); the
  admin can only reject it with a reason, and the seller keeps the live listing.

## Admin web session

Fixed in this release: the Edge middleware's access-token check threw
("3rd argument is not instance of ArrayBuffer") on every request, so each
request rotated the single-use refresh token and parallel requests (page loads,
link prefetches) raced and redirected to `/login`. See
`admin-web/src/lib/verify-admin-jwt.ts` and the single-flight refresh in
`admin-web/src/lib/admin-session-auth.ts`.
