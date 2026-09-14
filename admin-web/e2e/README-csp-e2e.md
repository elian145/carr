# L-02 style-src CSP e2e validation

`e2e/csp.spec.ts` proves that removing `'unsafe-inline'` from the production
`style-src` CSP directive (`admin-web/src/middleware.ts`) does not break
real page rendering.

The unauthenticated `/login` check always runs. The authenticated checks
(`/dashboard`, `/insights`, `/users`, `/listings`, and cross-page navigation)
log in through the **real** login form and the real `/api/admin-session` ->
`/api/auth/login` flow — no middleware bypass, no fake token. They require a
real backend and a real seeded admin account, and are **skipped** (not
faked) when those aren't configured.

## One-time local setup

```powershell
# 1. Seed a real admin (User + AdminAccount) into a throwaway SQLite DB.
$env:APP_ENV="testing"
$env:SMS_PROVIDER="console"
$env:DB_PATH="$env:TEMP\l02_e2e.db"
$env:JWT_SECRET_KEY="<any long random string>"
$env:E2E_ADMIN_USERNAME="e2e_admin"
$env:E2E_ADMIN_PASSWORD="<any test password>"
python admin-web/e2e/seed_test_admin.py

# 2. Start the real backend against that same DB (separate terminal, repo root).
$env:APP_ENV="testing"
$env:SMS_PROVIDER="console"
$env:DB_PATH="$env:TEMP\l02_e2e.db"
$env:JWT_SECRET_KEY="<same value as step 1>"
python -m kk.app_new   # listens on http://127.0.0.1:5000

# 3. Run the e2e suite (separate terminal, admin-web/).
$env:JWT_SECRET_KEY="<same value as step 1>"
$env:E2E_ADMIN_USERNAME="e2e_admin"
$env:E2E_ADMIN_PASSWORD="<same value as step 1>"
npx playwright test e2e/csp.spec.ts
```

`playwright.config.ts`'s `webServer` already defaults
`NEXT_PUBLIC_API_BASE=http://127.0.0.1:5000` and a CI JWT secret, matching
the backend started above — no admin-web env changes needed in CI beyond
`E2E_ADMIN_USERNAME`/`E2E_ADMIN_PASSWORD` and a running seeded backend.

`e2e/seed_test_admin.py` is test-only tooling: it does not modify anything
under `kk/`, and only ever writes to the throwaway SQLite file at `DB_PATH`.
