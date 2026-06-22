# Architecture

## Overview

CARZO (CarNet) is a Flutter client + Flask backend monorepo for a car marketplace with listings, chat, favorites, and admin tools.

## Production entry points

| Layer | Entry | Notes |
|-------|-------|-------|
| Flutter | `lib/main.dart` → `MyApp` | Production UI as `part of` library in `lib/app/carzo_shared.dart` + `lib/pages/` |
| Backend (prod) | `kk.wsgi:app` / `create_app()` in `kk/app_factory.py` | Do not use `kk/legacy/app.py` in production |
| Local dev API | `python -m kk.app_new` on **5000**, proxy `backend/server.py` on **5003** | App default `API_BASE` targets the proxy |

## Flutter layout

```
lib/
├── main.dart              # bootstrapAndRun(MyApp)
├── app/
│   ├── carzo_shared.dart  # Shared helpers + part library host (~1.6k lines)
│   ├── app_api_base.dart  # getApiBase()
│   ├── widgets/           # global_listing_card, listing_galleries, home_search_dialog, listing_network_image
│   ├── production_app.dart
│   ├── production_routes.dart
│   └── listing_shell.dart # Re-exports listing card / nav helpers
├── pages/
│   ├── home_page.dart, sell_flow_page.dart, …  # part of carzo_shared
│   ├── carzo_app/         # Simplified CarzoApp-only stubs (smoke tests)
│   └── …                  # Standalone screens (edit listing, my listings, …)
├── services/              # API, auth, WebSocket, push, config
│   ├── api_service.dart   # HTTP core + delegators (~650 lines)
│   └── api/               # api_http, api_auth, api_listings, api_chat, api_admin
└── shared/                # Reusable helpers, prefs, i18n
```

**Migration status:** Production screens are `part of '../app/carzo_shared.dart'` under `lib/pages/` (see `lib/pages/README.md`). Shared shell code lives in `carzo_shared.dart`; routes in `production_routes.dart`. Simplified **CarzoApp** stubs under `lib/pages/carzo_app/` remain for migration smoke tests.

## Backend layout

```
kk/
├── app_factory.py         # Application factory (production)
├── routes/                # REST + admin endpoints
├── models.py              # SQLAlchemy models
├── security.py            # Rate limits, sanitization
├── socketio_handlers.py   # Real-time chat
└── legacy/                # Old monolith; guarded, not for production
```

## Configuration

- **Flutter API URL:** `lib/services/config.dart` — override with `--dart-define=API_BASE=...` or in-app Settings → API.
- **Backend secrets:** `APP_ENV`, `SECRET_KEY`, `JWT_SECRET_KEY`, `DATABASE_URL` (required in production). See `docs/DEPLOY_ENV_CHECKLIST.md`.
- **Rate limiting:** Set `REDIS_URL` in production when running multiple Gunicorn workers.

## CI

| Check | Workflow / script |
|-------|-------------------|
| Flutter analyze + test | `.github/workflows/flutter_ci.yml` |
| Backend compile + smoke | `.github/workflows/backend_ci.yml` |
| Local mirror | `scripts/run_local_ci.py`, `scripts/run_local_checks.ps1` |

## Testing

- Flutter: `flutter test` (uses in-memory `test/fake_api_server.dart` — method-aware stub bound to [ApiService.testHttpClient])
- Backend: `python scripts/smoke_tests/test_backend_factory_smoke.py` (22 factory tests)
- Optional manual scripts: `kk/test_*.py` (require a running server unless noted)

All production legacy HTTP goes through `ApiService` (token refresh, shared errors, test mock client).
