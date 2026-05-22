# Scripts

| Directory | Purpose |
|-----------|---------|
| [`dev/`](dev/) | Local setup, firewall helpers, and `start_servers.ps1` |
| [`smoke_tests/`](smoke_tests/) | Manual and CI backend smoke scripts |
| [`one_off_migrations/`](one_off_migrations/) | Legacy SQLite repair scripts (prefer Alembic) |

**Render production** still uses repo-root [`start_render.sh`](../start_render.sh) as configured in `render.yaml`.

| Script | Purpose |
|--------|---------|
| [`verify_publish_ready.py`](verify_publish_ready.py) | Static checks (Firebase, icon, bundle id) — runs in CI |
| [`verify_production_host.py`](verify_production_host.py) | HTTP checks against deployed API (health, trust, legal, optional app links) |
| [`print_android_app_link_sha.py`](print_android_app_link_sha.py) | Print `ANDROID_SHA256_CERT_FINGERPRINTS` for Render from upload keystore |
| [`run_local_checks.ps1`](run_local_checks.ps1) | Flutter tests + static preflight + backend smoke (Windows) |
