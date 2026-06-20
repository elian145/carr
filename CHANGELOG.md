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

### Changed

- Support/legal defaults use `support@carzo.app` (removed `support@carlistings.com` client fallback).
- README release steps reference verify scripts and `--dart-define=API_BASE`.

- MIT `LICENSE` file (README previously referenced it without the file).
- `scripts/one_off_migrations/` for legacy SQLite repair scripts (moved from repo root).
- `scripts/dev/` and `scripts/smoke_tests/` for local tooling and CI smoke tests.
- `docs/DEPLOY_ENV_CHECKLIST.md` for Render production env vars.
- `assets/icon/app_icon.png` and `flutter_launcher_icons` config in `pubspec.yaml`.
- This changelog.

### Changed

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

### Changed

- Re-enabled analyzer rules on maintained Dart code (`lib/services/`, `lib/shared/`, `lib/pages/`); legacy remains excluded during migration.
- Added `logNonFatal()` for non-fatal error reporting (debug log + Sentry) across services and legacy part files.
- Gated Socket.IO JWT `?token=` query fallback to development/testing only.
- Added `docs/ARCHITECTURE.md`, corrected README/CHANGELOG drift, Dependabot, pip-audit in backend CI, Flutter coverage in CI.
- HTTP timeouts on legacy raw `http` calls; production warning when rate limits fall back to in-process storage without Redis.

- Migrated deprecated Flutter APIs in `lib/pages/` (Dropdown `initialValue`, `RadioGroup`, `ExpansibleController`, `withValues`).
- Migrated legacy `withOpacity` → `withValues` across all `lib/legacy/` part files.
- Enabled legacy analyzer (removed `lib/legacy/**` exclude); removed dead legacy helpers — **0 analyzer warnings**.
- Split auth/profile HTTP from `api_service.dart` into `lib/services/api/api_auth.dart` (24 methods via `_ApiServiceAuth`).

### Planned (not yet complete)

- Finish migrating production UI from `lib/legacy/` to `lib/pages/` (see `lib/legacy/README.md`).
- Re-enable full analyzer rules on legacy code (info-level `use_build_context_synchronously` in sell flow).
- Split remaining `api_service.dart` modules (listings, chat, admin) using `tools/split_api_service.py` boundaries.

## [1.0.0] - 2026-05-20

### Added

- Initial CARZO marketplace release track (Flutter client + Flask backend).
