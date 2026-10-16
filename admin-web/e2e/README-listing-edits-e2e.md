# Listing edits e2e (pending revisions of published listings)

`e2e/listing-edits.spec.ts` drives the real admin UI against a real backend:

- `/listing-edits` and `/listing-edits/<id>` redirect to `/login` when signed out
  (existing admin authentication / middleware);
- the "Listing edits" entry is reachable from the admin navigation;
- a seller's pending edit of an active listing is listed while the public
  listing still shows the approved data;
- the review page shows approved vs proposed values, and **Approve & publish**
  publishes them on the same listing id.

The signed-out checks always run. The authenticated checks are skipped (not
faked) unless the seeds below were run against the backend's database.

```powershell
$env:APP_ENV="testing"; $env:SMS_PROVIDER="console"
$env:DB_PATH="$env:TEMP\le_e2e.db"
$env:JWT_SECRET_KEY="<any long random string>"
$env:E2E_ADMIN_USERNAME="e2e_admin"; $env:E2E_ADMIN_PASSWORD="<test password>"
$env:E2E_SEED_OUT="$env:TEMP\le_seed.json"

python admin-web/e2e/seed_test_admin.py      # admin login (see README-csp-e2e.md)
python admin-web/e2e/seed_listing_edit.py    # active listing + pending owner edit

python -m kk.app_new                          # backend on :5000 (separate terminal)

cd admin-web                                  # production build + server
$env:NEXT_PUBLIC_API_BASE="http://127.0.0.1:5000"
npm run build; npx next start -p 3100         # separate terminal
$env:ADMIN_WEB_BASE_URL="http://127.0.0.1:3100"
npx playwright test e2e/listing-edits.spec.ts
```

Test-only tooling: nothing under `kk/` is changed and only the throwaway
SQLite file at `DB_PATH` is written.
