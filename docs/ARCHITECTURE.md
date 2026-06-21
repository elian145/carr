# Architecture

## Overview

CARZO (CarNet) is a Flutter client + Flask backend monorepo for a car marketplace with listings, chat, favorites, and admin tools.

## Production entry points

| Layer | Entry | Notes |
|-------|-------|-------|
| Flutter | `lib/main.dart` → `MyApp` | Production UI in `lib/pages/production/` (part library) |
| Backend (prod) | `kk.wsgi:app` / `create_app()` in `kk/app_factory.py` | Do not use `kk/legacy/app.py` in production |
| Local dev API | `python -m kk.app_new` on **5000**, proxy `backend/server.py` on **5003** | App default `API_BASE` targets the proxy |

## Flutter layout

```
lib/
├── main.dart              # bootstrapAndRun(MyApp)
├── pages/
│   ├── production/        # Production UI (part library, ~25k lines)
│   └── …                  # Standalone screens + CarzoApp-only stubs
├── app/                   # production_app, listing_shell, CarzoApp (migration tests)
├── services/              # API, auth, WebSocket, push, config
│   ├── api_service.dart   # HTTP core + delegators (~650 lines)
│   └── api/               # api_http, api_auth, api_listings, api_chat, api_admin
└── shared/                # Reusable helpers, prefs, i18n
```

**Migration status:** Production screens moved from `lib/legacy/` to `lib/pages/production/`. Standalone extracts under `lib/pages/` (e.g. `home_page.dart`, `sell_page.dart`) remain for `CarzoApp` smoke tests until each production screen is fully ported out of the part library. See `lib/pages/production/README.md`.

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
