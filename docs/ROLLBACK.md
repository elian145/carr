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
