# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Flutter tests boot production `legacy.MyApp` with shared `test/fake_api_server.dart`.
- `test/carzo_app_smoke_test.dart` for the refactor `CarzoApp` shell.
- `scripts/verify_publish_ready.py` static store preflight (CI on Flutter + backend).
- Backend smoke coverage for `/api/config/trust`, `/terms`, and `/privacy`.
- CI prod `appbundle` build (`--flavor prod`).

### Changed

- Support/legal defaults use `support@carzo.app` (removed `support@carlistings.com` client fallback).

- MIT `LICENSE` file (README previously referenced it without the file).
- `scripts/one_off_migrations/` for legacy SQLite repair scripts (moved from repo root).
- `scripts/dev/` and `scripts/smoke_tests/` for local tooling and CI smoke tests.
- `docs/DEPLOY_ENV_CHECKLIST.md` for Render production env vars.
- `assets/icon/app_icon.png` and `flutter_launcher_icons` config in `pubspec.yaml`.
- This changelog.

### Removed

- Accidental repo-root scratch files (`tash list`, `*_files.txt`, local test images).
- Root-level `migrate_*.py`, `test_*.py`, and dev setup scripts (relocated under `scripts/`).

### Changed

- `.gitignore` patterns for common accidental CLI artifacts and scratch listings.
- Backend CI runs `scripts/smoke_tests/test_backend_factory_smoke.py`.
- README and `tools/windows/start_app.ps1` point to `scripts/dev/start_servers.ps1`.

## [1.0.0] - 2026-05-20

### Added

- Initial CARZO marketplace release track (Flutter client + Flask backend).
