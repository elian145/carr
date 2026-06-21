# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Flutter tests boot production `ProductionApp` with shared `test/fake_api_server.dart`.
- `scripts/verify_publish_ready.py` static store preflight (CI on Flutter + backend).
- Backend smoke coverage for `/api/config/trust`, `/terms`, and `/privacy`.
- CI prod `appbundle` build (`--flavor prod`).
- `scripts/verify_production_host.py` and weekly/manual GitHub workflow for deployed API checks.
- `docs/PAYMENTS.md` (off-platform payments; no production payment gateway).
- `signing.properties.example` for Play upload setup.
- `scripts/print_android_app_link_sha.py` for Render `ANDROID_SHA256_CERT_FINGERPRINTS`.
- `scripts/run_local_checks.ps1` to mirror CI locally.
- MIT `LICENSE` file (README previously referenced it without the file).
- `scripts/one_off_migrations/` for legacy SQLite repair scripts (moved from repo root).
- `scripts/dev/` and `scripts/smoke_tests/` for local tooling and CI smoke tests.
- `docs/DEPLOY_ENV_CHECKLIST.md` for Render production env vars.
- `assets/icon/app_icon.png` and `flutter_launcher_icons` config in `pubspec.yaml`.
- Widget tests: profile, sell step 1, chat list/conversation, car detail, my listings, favorites, login, signup, recently viewed; ApiService integration against mock API.
- Backend smoke: car update/delete owner flow, update forbidden for non-owner, recently viewed GET/POST/clear, forgot/reset password via phone, chat send by public car id, favorites, filtered `/api/cars`, mark sold/active, paginated my-listings, verified Socket.IO send, saved-search CRUD, chat list, auth refresh/logout, email verify token, dealer profile by public id, change password, update profile, register confirm, user/listing report and block flow.

### Changed

- Support/legal defaults use `support@carzo.app` (removed `support@carlistings.com` client fallback).
- README release steps reference verify scripts and `--dart-define=API_BASE`.
- Renamed sell draft prefs modules to `sell_draft_prefs.dart` / `sell_draft_list.dart` (`SellDraftPrefs`, `SellDraftList`); SharedPreferences key strings unchanged.
- Removed `/legacy_*` route aliases from `buildProductionRoutes()`.
- Production entry uses `legacy.MyApp` from `lib/main.dart`; `CarzoApp` remains for migration smoke tests only.
- `SellDraftList` delegates shared logic to `SellDraftArchive`.
- Split `sell_page.dart` into extension parts under `lib/pages/sell/` (~809-line shell + 6 modules).
- Split `chat_pages.dart` into extension parts under `lib/pages/chat/` (~1,072-line shell + 9 modules); `tools/split_chat_pages.py` for regeneration from monolith.
- Unified sell draft prefs: merged `SellListingDraftPrefs` into `SellDraftPrefs` (`loadListingDraft` / `saveListingDraft` / `clearListingDraft`); SharedPreferences key strings unchanged.
- Widget tests: car detail cached-listing UI check; `AuthService.adoptTestSession` / `resetTestSession` for test auth; `AuthService` registered with `ChangeNotifierProvider.value` so the singleton is not disposed between tests.
- `ApiService.testHttpClient` + in-memory `FakeApiServer` mock client (replaces loopback `HttpServer` in tests); chat list empty-state widget test; sell flow still covered by route smoke.
- Sell page widget test with `CarSpecIndex.debugLoadWithResult` test hook; `CarSpecIndex.loadWithResult` caches in-flight load.
- Extracted [ApiException] to `lib/services/api_exception.dart`; added `tools/split_api_service.py` scaffold for the next ApiService module split.
- Login widget tests and mock-API auth login test; skip Socket.IO when [ApiService.testHttpClient] is bound.
- `.gitignore` patterns for common accidental CLI artifacts and scratch listings.
- Backend CI runs `scripts/smoke_tests/test_backend_factory_smoke.py`.
- README and `tools/windows/start_app.ps1` point to `scripts/dev/start_servers.ps1`.
- Re-enabled analyzer rules on maintained Dart code; legacy included via `main_legacy.dart` part library — **0 analyzer issues**.
- Added `logNonFatal()` for non-fatal error reporting (debug log + Sentry) across services and legacy part files.
- Gated Socket.IO JWT `?token=` query fallback to development/testing only.
- Added `docs/ARCHITECTURE.md`, corrected README/CHANGELOG drift, Dependabot, pip-audit in backend CI, Flutter coverage in CI.
- HTTP timeouts on legacy raw `http` calls; production warning when rate limits fall back to in-process storage without Redis.
- Split `api_service.dart` into `lib/services/api/{api_http,api_auth,api_listings,api_chat,api_admin}.dart` (~650-line delegator shell).
- Cleared legacy deprecated APIs and style lints (RadioGroup, SharePlus, `Color.r/g/b`, etc.) — zero analyzer infos.
- Migrated deprecated Flutter APIs in `lib/pages/` (Dropdown `initialValue`, `RadioGroup`, `ExpansibleController`, `withValues`).
- Migrated legacy `withOpacity` → `withValues` across all `lib/legacy/` part files.
- Bumped backend dependencies for pip-audit (Flask 3.1.3, Flask-CORS 6, Flask-SocketIO 5.6.1, Werkzeug, Pillow, etc.) and removed unused `python-jose`.
- Legacy profile/favorites/signup OTP use `ApiService` (token refresh) instead of raw `http`; `FakeApiServer` matches `/auth/me` and `/api/my_listings` response shapes.
- `DeepLinkService` skips platform app-link plugins when `ApiService.isTestHttpClientBound` (widget tests).
- Home feed, my listings, comparison quick-sell, and sell create/list flows route HTTP through `ApiService` (`getCarsRaw`, `getMyListingsCompat`, `createCar`, uploads).
- Car detail and sell video upload use `ApiService.getCarDetail` / `uploadCarVideos` (custom MIME sniffing preserved via multipart builder).
- Method-aware `FakeApiServer` stub; ApiService integration tests; backend create-car smoke.
- Aligned `kk/requirements_min.txt` with patched core versions; `backend/requirements.txt` redirects to `kk/requirements.txt`.
- `run_local_checks.ps1` runs `pip-audit` after backend smoke.
- `ApiService.initializeTokens` keeps an in-memory session when secure storage is empty or unreadable.
- Sell steps 2–5 and chat send widget tests; mock chat send returns a `message` envelope echoing posted content.
- Sell step 4 draft dispose avoids ancestor lookup after deactivation (widget tests).
- `AnalyticsService` routes HTTP through `ApiService` (mockable in tests); settings/comparison/dealers/analytics widget smokes.
- Edit profile, forgot/reset password widget tests and auth recovery API smoke.
- Help center, verify-email, and dealer profile widget tests; dealer profile and verify-email API tests.
- Saved searches empty-state widget test; auth profile API tests (`changePassword`, `updateProfile`, `confirmSignup`); `TrustConfig` uses mock HTTP client in tests.
- Sell step 1→2 navigation widget test; authenticated saved searches list test; saved-search update/sync/delete API tests.
- Admin reports empty-queue widget test; moderation API tests (`reportUser`, `blockUser`, admin report updates); backend smoke for report/block flow.

### Planned (not yet complete)

- Finish migrating production UI from `lib/legacy/` to `lib/pages/` (see `lib/legacy/README.md`).
- Set `REDIS_URL` in production for multi-worker rate limits (see `docs/DEPLOY_ENV_CHECKLIST.md`).

## [1.0.0] - 2026-05-20

### Added

- Initial CARZO marketplace release track (Flutter client + Flask backend).
