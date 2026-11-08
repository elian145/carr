# Owner actions (code cannot complete these)

Status of every item below: **NOT DONE - pending owner**. Nothing here has been
performed or verified by an engineer or an agent. No secrets belong in this file.
Finding IDs refer to the CarNet audit plan (F-xx) and `PRODUCTION_AUDIT.md` (C-xx).

## A. Audit findings that need an owner decision or external access

- [ ] **F-11** Freeze app identity: Android prod is `com.carnetiq.app`; dev/stage, Android namespace and iOS use `com.carzo.app`. Decide the final bundle/package IDs. Move API, Android App Links and iOS Universal Links off the `carr-5hrm.onrender.com` subdomain onto a custom domain (update AASA, `assetlinks.json`, `Runner.entitlements`, `codemagic.yaml`). Configure force-update. Settle "Carzo" vs "CarNet" branding (scheme, emails, support domain).
- [ ] **F-14** Provide device/emulator E2E coverage: saved-search, chat, Kurdish (RTL) journeys, signup -> list -> moderate -> visible, delete account. `integration_test/app_smoke_test.dart` only checks that `MyApp` builds. Needs a staging backend and test accounts.
- [ ] **F-29** Legal/privacy: account deletion keeps chat messages and chat media visible to the counterpart. Get legal review for Iraq. Make the Google Play Data Safety form and Apple App Privacy answers match the live `/privacy` and `/delete-account` pages. (Code item, done: password-reset and e-mail-verification tokens are stored as HMAC hashes, are single-use and expire; `RETENTION_AUTH_TOKEN_PURGE=1` additionally deletes expired rows - see `docs/RETENTION_CLEANUP.md`. Not an owner action.)
- [ ] **F-30** Verify infrastructure in the Render, Neon and Redis dashboards: stale Oregon `carr-worker`/`carr-beat` services vs Frankfurt `carr-worker-fra`/`carr-beat-fra` (duplicate beat = duplicate notifications); web service region and plan; free-plan sleeping vs `keep_warm.yml`; Redis reachability (boot fails without it); migrations on every web start; Neon backups/PITR; rollback drill (`docs/ROLLBACK.md` checklist is unchecked).
- [ ] **F-33** Check the real production auto-moderation mode (admin API): shadow vs live, `AUTO_MODERATION_ALLOW_LIVE`, AI provider, kill switch. The OpenAI adapter has never run against the real API; the kill switch does not stop AI spend; videos are not inspected; spam heuristic is English-only. Keep manual review (`listing_require_approval=true`) until decided.
- [ ] **C-5** Payments: product decision (build IAP with server-side receipt validation, or descope and keep featured listings admin-only/free). `docs/PAYMENTS.md` documents it as intentional/off-platform. Affects store review answers.

## B. Production verification of items closed in code

- [ ] **C-1** Realtime socket caps/rate limits: confirm limits and `REDIS`-backed behaviour under load on production.
- [ ] **C-2** REST chat image/video sends emit socket + push + notification: send on production with two accounts and a physical device.
- [ ] **C-3** Keyword search: confirm the Postgres full-text trigger/index exists on production and `q` returns ranked results.
- [ ] **C-6** Signed production AAB: confirm the Play upload key, Play App Signing enrolment and that the release build used the production keystore.
- [ ] **F-19 (production switch, left OFF)** Admin token separation (ES256) is implemented but must stay inactive until the owner performs the staged rollout in `docs/F19_ADMIN_TOKEN_SEPARATION.md` (generate keypair outside the repo, set the private key on the API only, public key on admin-web, verify, then remove `JWT_SECRET_KEY` from admin-web).
- [ ] **F-20** Create separate Firebase projects for dev and stage (console action), download their config files, and replace the placeholders; confirm test pushes/analytics no longer reach production. Then supply: the dev and stage Firebase project IDs (`scripts/firebase_expected_projects.json` or repo/CI variables `CARNET_FIREBASE_DEV_PROJECT_ID` / `CARNET_FIREBASE_STAGE_PROJECT_ID`), confirm the prod ID pinned there (`carzo-prod`), set `CARNET_FIREBASE_STRICT=1` in GitHub, and set `FIREBASE_EXPECTED_PROJECT_ID` (every backend deployment) and `FIREBASE_PRODUCTION_PROJECT_ID` (non-prod deployments) on the servers. Until then `verify_firebase_isolation.py --release --flavor dev|stage` fails closed.

## C. Store, compliance and operations

- [ ] Store signing: Android upload key + Play App Signing; iOS certificates/profiles, TestFlight; keep keystores and passwords out of git.
- [ ] Privacy disclosures: Play Data Safety, Apple App Privacy, in-app and web privacy policy consistent with actual data handling (see F-29).
- [ ] R2 lifecycle: apply the private-bucket lifecycle/retention rules per `docs/R2_PRIVATE_BUCKET_LIFECYCLE.md` in the Cloudflare dashboard; verify uploads work from the deployed image.
- [ ] Backup/restore: confirm Neon backups/PITR, perform and record a restore drill; record R2 backup approach.
- [ ] **Build numbering:** look up the highest iOS build in App Store Connect and Android versionCode in Play, set Codemagic variables `BUILD_NUMBER_OFFSET` (above both) and `USE_MONOTONIC_BUILD_NUMBER=1` (`scripts/compute_build_number.py`). Until then iOS uses the legacy `CM_BUILD_ID` derivation.
- [ ] **Toolchain:** confirm Flutter `3.47.5` (`.flutter-version`, pinned in CI/Codemagic) is the version you ship with; Python is pinned to Render's `.python-version` (3.11.9) in Docker/CI.
- [ ] Physical-device tests: Android and iOS, App Links/Universal Links, push delivery (dev/stage/prod), chat incoming/outgoing, Maps/Places, photo upload on slow mobile data, Kurdish/Arabic RTL, call button (`tel:` with stored phone formats).
