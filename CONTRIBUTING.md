# Contributing

Thanks for helping improve CARZO / CarNet. This guide covers local setup, expectations for PRs, and where to look in the monorepo.

## Prerequisites

- Flutter (stable) matching CI
- Python 3.11+ with a venv
- Optional: Node.js for `admin-web/`
- Docker only if you prefer the root `Dockerfile` for the API

## Local setup

1. Clone the repo and install Flutter deps: `flutter pub get`
2. Backend deps: `python -m venv .venv`, activate it, then `pip install -r kk/requirements.txt`
3. Start API + proxy (from repo root):
   - Windows: `.\scripts\dev\start_servers.ps1`
   - Manual: `python -m kk.app_new` on port **5000**, then `python backend/server.py` on **5003**
4. Run the app with a flavor: `flutter run --flavor dev` (pass `--dart-define=API_BASE=...` if needed)

Production API entry is `kk.wsgi:app` / `create_app()` — never the retired `kk.app` monolith. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Workflow

1. Fork (or use a branch on the shared remote)
2. Create a focused branch from `main`
3. Make the smallest change that solves one problem
4. Add or update tests when behavior changes
5. Note user-facing / notable work in [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]`
6. Open a pull request against `main`

### Pull requests

- Prefer one concern per PR (easier review and revert)
- Describe **why**, not only what changed
- Link related issues when applicable
- Do not commit secrets (`.env`, `signing.properties`, keystores, API keys)
- Do not add one-shot scratch scripts under `tools/` unless they are maintained tooling

## Code layout (where to edit)

| Area | Path |
|------|------|
| Flutter production UI | `lib/pages/` (`part of` `lib/app/carzo_shared.dart`) + `lib/app/` |
| API client | `lib/services/api_service.dart` + `lib/services/api/` |
| Flask API | `kk/routes/`, `kk/models.py`, `kk/app_factory.py` |
| Schema changes | Alembic under `migrations/` — run `flask db migrate` / `upgrade` via the app’s usual env |
| Admin web | `admin-web/` |
| Docs / deploy | `docs/`, especially `DEPLOY_ENV_CHECKLIST.md` |

Prefer extending existing modules over new top-level packages. Match naming and style of nearby files.

## Checks before you push

Mirror CI locally when practical:

```bash
# Full local mirror (analyze, flutter test, publish preflight, backend smoke, compileall, pip-audit)
# Windows:
.\scripts\run_local_checks.ps1

# Cross-platform:
python scripts/run_local_ci.py
```

Targeted:

```bash
flutter analyze --no-fatal-infos
flutter test
python scripts/smoke_tests/test_backend_factory_smoke.py
```

Flutter tests use `test/fake_api_server.dart` (in-memory mock on `ApiService.testHttpClient`). See [test/README.md](test/README.md).

CI workflows: `.github/workflows/flutter_ci.yml`, `backend_ci.yml`, `admin_web_ci.yml`.

## Commit messages

Use clear, imperative subjects (e.g. `Fix chat read receipts on reconnect`). Audit-fix commits in this repo often use `Fix H-NN/M-NN/L-NN: …` when closing a tracked finding — follow that if you are working the same list.

## Security / product notes

- Never weaken auth, chat room membership, or upload validation without an explicit security review
- Production needs real secrets and Postgres; see [docs/DEPLOY_ENV_CHECKLIST.md](docs/DEPLOY_ENV_CHECKLIST.md)
- Payments are off-platform — see [docs/PAYMENTS.md](docs/PAYMENTS.md)

## Questions

Open a GitHub issue, or check [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the README first.
