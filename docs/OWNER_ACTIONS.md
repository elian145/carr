# Owner actions (code cannot complete these)

Status of every item below: **NOT DONE - pending owner**. Nothing here has been
performed or verified by an engineer or an agent. No secrets belong in this file.
Finding IDs refer to the CarNet audit plan (F-xx) and `PRODUCTION_AUDIT.md` (C-xx).

## A. Audit findings that need an owner decision or external access

- [ ] **F-11** Freeze app identity: Android prod is `com.carnetiq.app`; dev/stage, Android namespace and iOS use `com.carzo.app`. Decide the final bundle/package IDs. Move API, Android App Links and iOS Universal Links off the `carr-5hrm.onrender.com` subdomain onto a custom domain (update AASA, `assetlinks.json`, `Runner.entitlements`, `codemagic.yaml`). Configure force-update. Settle "Carzo" vs "CarNet" branding (scheme, emails, support domain).
- [ ] **F-14** Provide device/emulator E2E coverage: saved-search, chat, Kurdish (RTL) journeys, signup -> list -> moderate -> visible, delete account. `integration_test/app_smoke_test.dart` only checks that `MyApp` builds. Needs a staging backend and test accounts.
- [ ] **F-29** Legal/privacy: account deletion keeps chat messages and chat media visible to the counterpart. Get legal review for Iraq. Make the Google Play Data Safety form and Apple App Privacy answers match the live `/privacy` and `/delete-account` pages. (Password-reset token storage is a code item, owned by Agent C.)
- [ ] **F-30** Verify infrastructure in the Render, Neon and Redis dashboards: stale Oregon `carr-worker`/`carr-beat` services vs Frankfurt `carr-worker-fra`/`carr-beat-fra` (duplicate beat = duplicate notifications); web service region and plan; free-plan sleeping vs `keep_warm.yml`; Redis reachability (boot fails without it); migrations on every web start; Neon backups/PITR; rollback drill (`docs/ROLLBACK.md` checklist is unchecked).
- [ ] **F-33** Check the real production auto-moderation mode (admin API): shadow vs live, `AUTO_MODERATION_ALLOW_LIVE`, AI provider, kill switch. The OpenAI adapter has never run against the real API; the kill switch does not stop AI spend; videos are not inspected; spam heuristic is English-only. Keep manual review (`listing_require_approval=true`) until decided.
- [ ] **C-5** Payments: product decision (build IAP with server-side receipt validation, or descope and keep featured listings admin-only/free). `docs/PAYMENTS.md` documents it as intentional/off-platform. Affects store review answers.

## B. Production verification of items closed in code

- [ ] **C-1** Realtime socket caps/rate limits: confirm limits and `REDIS`-backed behaviour under load on production.
- [ ] **C-2** REST chat image/video sends emit socket + push + notification: send on production with two accounts and a physical device.
- [ ] **C-3** Keyword search: confirm the Postgres full-text trigger/index exists on production and `q` returns ranked results.
- [ ] **C-6** Signed production AAB: confirm the Play upload key, Play App Signing enrolment and that the release build used the production keystore.
- [ ] **F-19 (production switch, left OFF)** Admin token separation (ES256) is implemented but must stay inactive until the owner performs the staged rollout in `docs/F19_ADMIN_TOKEN_SEPARATION.md` (generate keypair outside the repo, set the private key on the API only, public key on admin-web, verify, then remove `JWT_SECRET_KEY` from admin-web).
- [ ] **F-20** Create separate Firebase projects for dev and stage (console action), download their config files, and replace the placeholders; confirm test pushes/analytics no longer reach production.

## C. Store, compliance and operations

- [ ] Store signing: Android upload key + Play App Signing; iOS certificates/profiles, TestFlight; keep keystores and passwords out of git.
- [ ] Privacy disclosures: Play Data Safety, Apple App Privacy, in-app and web privacy policy consistent with actual data handling (see F-29).
- [ ] R2 lifecycle: apply the private-bucket lifecycle/retention rules per `docs/R2_PRIVATE_BUCKET_LIFECYCLE.md` in the Cloudflare dashboard; verify uploads work from the deployed image.
- [ ] Backup/restore: confirm Neon backups/PITR, perform and record a restore drill; record R2 backup approach.
- [ ] Physical-device tests: Android and iOS, App Links/Universal Links, push delivery (dev/stage/prod), chat incoming/outgoing, Maps/Places, photo upload on slow mobile data, Kurdish/Arabic RTL, call button (`tel:` with stored phone formats).
