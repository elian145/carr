# F-19: admin token separation and admin-web hardening

Audit F-19: the admin Next.js service held the API's `JWT_SECRET_KEY` (HS256). Compromising
admin-web let an attacker mint a valid token for **any** user. This document describes the
opt-in fix, the provisioning of its keys, the staged roll-out, the rollback and the pre-launch
verification. Nothing changes until the new env vars are set.

Companion documents: [`RELEASE_POLICY_FORCE_UPDATE.md`](RELEASE_POLICY_FORCE_UPDATE.md), [`DEPLOY_ENV_CHECKLIST.md`](DEPLOY_ENV_CHECKLIST.md).

## Release policy (owner decision)

**The F-19 split-secret (ES256 admin token) feature stays DISABLED until production configuration
and staged compatibility tests are ready.** "Disabled" means: no `ADMIN_JWT_PRIVATE_KEY`,
`ADMIN_JWT_PUBLIC_KEY` or `ADMIN_JWT_ENFORCE` in the production `carr` service, and no
`ADMIN_JWT_PUBLIC_KEY` in `carr-admin`; `carr-admin` keeps the legacy `JWT_SECRET_KEY`. The
code is merged-dark: with none of the variables set the API and admin-web behave exactly as before
(`test_flag_off_registers_nothing_and_issues_nothing`).

Do not set any `ADMIN_JWT_*` variable in production without a separate, explicit decision and a
completed staging run of this document (pre-launch checklist at the end).

Status of the code: the token-issuing hunk in `kk/routes/auth.py` (`_access_token_for_user` /
`_refresh_token_for_user` calling `issue_admin_token`, commit `02a3185`) **is already part of the
base this document was written against (`1aab2ef`, Draft PR #35 head)**. Nothing has to be applied by
hand any more; the test module's `_emulate_issuance_hunk` fixture is a no-op because
`kk.routes.auth` now exposes `issue_admin_token`.

## Design

| Token | Signed by | Verified by | Notes |
| --- | --- | --- | --- |
| User tokens (mobile app, OTP, password) | `JWT_SECRET_KEY`, HS256 | API | unchanged |
| Admin-scoped tokens (`account_scope=admin`, only after `AdminAccount` dashboard login) | `ADMIN_JWT_PRIVATE_KEY`, ES256 (EC P-256) | API (`ADMIN_JWT_PUBLIC_KEY`/derived) and admin-web (`ADMIN_JWT_PUBLIC_KEY`) | admin-web holds a **public** key only |

What F-19 protects and what it does not: after the full roll-out a compromised admin-web holds
nothing that can sign a token, and a leaked API `JWT_SECRET_KEY` can no longer produce an *admin*
session (`ADMIN_JWT_ENFORCE=1`). It does **not** protect user tokens against a leak of the API's own
`JWT_SECRET_KEY`: user tokens remain HS256 under that secret.

API side (`kk/admin_tokens.py`, hook in `kk/app_factory.py`, settings in `kk/config.py`):

* An ES256 token is accepted only if the signature verifies with the admin public key, it carries
  `account_scope=admin` **and** `is_admin`, **and** it is presented to an admin route (`/api/admin/*`,
  `/api/admin`) or to `/api/auth/me|refresh|logout` (what the dashboard needs). Anywhere else (e.g.
  `/api/user/...`) it is a 401. `/api/administrator`, `/api/auth/login`, `/api/auth/me/x` are *not*
  admin routes (`test_admin_route_scope_helper`).
* HS256 tokens keep working exactly as before (user tokens) - unless `ADMIN_JWT_ENFORCE=1`, in
  which case an HS256 token carrying admin claims (`account_scope=admin` **or** `is_admin=true`) is
  rejected everywhere (including `/api/auth/refresh`), so a leaked `JWT_SECRET_KEY` can no longer
  produce an admin session.
* `alg` is constrained to `HS256`/`ES256`; the key is chosen per algorithm (HS256 -> only the shared
  secret, ES256 -> only the admin public key), so `none`, RS256 and HS256-signed-with-the-public-key
  confusion attacks are rejected.
* Every admin-signed token (access and refresh) is stamped with `iss` (`ADMIN_JWT_ISSUER`, default
  `carnet-api`) and `aud` (`ADMIN_JWT_AUDIENCE`, default `carnet-admin-web`). The API
  (`_decode_key_for`) and admin-web (`verifyAdminAccessJwt`, also for a freshly rotated access
  token) **require both**: a missing or different `iss`/`aud` is a 401 / no session. The defaults are
  public constants, so no new variable is needed; the check is never skipped when a variable is unset
  (blank = default). Tokens issued before this change lack the claims and are rejected: admins
  sign in again once. Legacy HS256 admin tokens are minted by flask-jwt-extended without `iss`/`aud`
  and are not covered (that path is removed by stage 3).
* Revocation (`jti` blocklist, inactive users, `tokens_invalid_before`) is unchanged: the admin
  tokens carry the same `jti/iat/sub/type/fresh` claims.
* Only dashboard logins (`POST /api/auth/login` with `"account_scope": "admin"` for an `AdminAccount`)
  mint admin scope; a mobile/OTP/password login never does, even for a user with `is_admin` (ADM-1).
  A user who is the principal of an `AdminAccount` cannot use the mobile password login at all (generic
  invalid-credentials response).
* `/api/auth/refresh` preserves admin scope only from the presented refresh token **and** an active
  `AdminAccount` principal; a refresh therefore re-issues an ES256 pair when the keys are configured.
* Token lifetimes (`kk/config.py`): access `JWT_ACCESS_TOKEN_MINUTES` (default 30, clamped 15-60),
  refresh `JWT_REFRESH_TOKEN_DAYS` (default 30, clamped 1-90). Admin-signed tokens use the same TTLs.

admin-web (`admin-web/src/lib/verify-admin-jwt.ts`, `admin-session-auth.ts`):

* Verifies ES256 with WebCrypto against `ADMIN_JWT_PUBLIC_KEY`. No shared secret needed.
* Production fails closed (no session at all) unless `ADMIN_JWT_PUBLIC_KEY` or the legacy
  `JWT_SECRET_KEY` is set.
* With the public key set and no secret, HS256 cookies are rejected (cannot be verified).
* admin-web never sees the refresh-token signing key either (refresh tokens are opaque to it and
  are exchanged at the API).
* The edge check is a gate only; the API verifies every proxied request again. When the edge cannot
  verify the access cookie it falls back to a refresh rotation against the API with the refresh cookie
  (`resolveAdminAccessToken`).

## Environment variables

| Var | Service | Meaning |
| --- | --- | --- |
| `ADMIN_JWT_PRIVATE_KEY` | `carr` (API) **only** | EC P-256 private key, unencrypted PKCS8 PEM (newlines may be literal `\n`) |
| `ADMIN_JWT_PUBLIC_KEY` | `carr` (optional, derived from the private key) and `carr-admin` | matching SPKI public key PEM (admin-web also accepts the bare base64 body) |
| `ADMIN_JWT_ENFORCE` | `carr` | `1` = reject HS256 tokens carrying admin claims (needs the private key on the same service) |
| `ADMIN_ALLOWED_ORIGINS` | `carr-admin` (optional) | CSRF allow-list, see below |
| `ADMIN_JWT_ISSUER` | `carr` and `carr-admin` (optional) | expected/stamped `iss` of admin-signed tokens; default `carnet-api`. Set to the SAME value on both services or on neither |
| `ADMIN_JWT_AUDIENCE` | `carr` and `carr-admin` (optional) | expected/stamped `aud` of admin-signed tokens; default `carnet-admin-web`. Same rule as above |
| `JWT_SECRET_KEY` | `carr` (always); `carr-admin` (legacy only, removed in stage 3a) | HS256 secret of **user** tokens |

The names are read in `kk/config.py` (`admin_jwt_private_key_pem`, `admin_jwt_public_key_pem`,
`admin_jwt_enforce_enabled`) and `admin-web/src/lib/admin-session-auth.ts` (`ADMIN_JWT_PUBLIC_KEY`,
`JWT_SECRET_KEY`). `render.yaml` declares them with `sync: false` (values live only in the Render
dashboard and a Blueprint sync never overwrites them).

Boot-time validation (API): invalid / non-P-256 / encrypted keys, a public key that does not match
the private key, or `ADMIN_JWT_ENFORCE` without the private key, make the API refuse to start
(`RuntimeError`) instead of silently running with a weaker mode
(`test_enforce_without_keys_refuses_to_boot`, `test_enforce_with_public_key_only_refuses_to_boot`,
`test_non_p256_and_garbage_and_mismatched_keys_refuse_to_boot`). **Consequence for operations:** never
unset the keys while `ADMIN_JWT_ENFORCE=1` is still set - that deploy cannot boot.

## Signing-key provisioning

Generate the pair **outside the repository working tree** (the repo `.gitignore` has no `*.pem` rule,
so a key file left inside it can be committed by `git add .`). Do it on the machine of the person who
will paste the values into the Render dashboard; no CI, no shared drive.

OpenSSL 3 on Linux/macOS, or Git-for-Windows' `openssl.exe` (e.g.
`C:\Program Files\Git\usr\bin\openssl.exe`) in PowerShell. Use `-out`, not shell redirection or
pipes (Windows PowerShell 5.1 re-encodes redirected output):

```
openssl ecparam -name prime256v1 -genkey -noout -out admin_jwt_ec.pem
openssl pkcs8 -topk8 -nocrypt -in admin_jwt_ec.pem -out admin_jwt_private.pem
openssl pkey -in admin_jwt_private.pem -pubout -out admin_jwt_public.pem
```

Delete the intermediate file (`admin_jwt_ec.pem`: Linux `shred -u admin_jwt_ec.pem`, Windows
`Remove-Item admin_jwt_ec.pem`). Check the result:

```
openssl pkey -in admin_jwt_private.pem -noout -text      # must show "ASN1 OID: prime256v1" / "NIST CURVE: P-256"
head -n 1 admin_jwt_private.pem                           # -----BEGIN PRIVATE KEY-----   (PowerShell: Get-Content admin_jwt_private.pem -TotalCount 1)
head -n 1 admin_jwt_public.pem                            # -----BEGIN PUBLIC KEY-----
```

The key must be **unencrypted** (`-nocrypt`): the API refuses a passphrase-protected key. Optionally
run the API's own validator against the pair from the repo root, using the project virtualenv
(no database needed; prints `ok` or raises `RuntimeError` without echoing key material):

```
# bash
ADMIN_JWT_PRIVATE_KEY="$(cat admin_jwt_private.pem)" ADMIN_JWT_PUBLIC_KEY="$(cat admin_jwt_public.pem)" \
  python -c "from kk.admin_tokens import _load_settings as l; s=l(); print('ok', 'enforce=%s' % s.enforce)"
# PowerShell
$env:ADMIN_JWT_PRIVATE_KEY = Get-Content admin_jwt_private.pem -Raw
$env:ADMIN_JWT_PUBLIC_KEY  = Get-Content admin_jwt_public.pem  -Raw
python -c "from kk.admin_tokens import _load_settings as l; s=l(); print('ok', 'enforce=%s' % s.enforce)"
Remove-Item Env:ADMIN_JWT_PRIVATE_KEY, Env:ADMIN_JWT_PUBLIC_KEY
```

Where each key goes:

| Key | `carr` (API) | `carr-admin` (admin-web) | Anywhere else |
| --- | --- | --- | --- |
| Private (`admin_jwt_private.pem`) | **yes** (`ADMIN_JWT_PRIVATE_KEY`) | **never** | password manager / offline secret store only; never git, chat, tickets, CI logs, screenshots |
| Public (`admin_jwt_public.pem`) | optional (`ADMIN_JWT_PUBLIC_KEY`; derived from the private key when omitted - if set it must match) | **yes** (`ADMIN_JWT_PUBLIC_KEY`) | may be shared; it cannot sign |

Storing them in the Render dashboard:

* Open the service (`carr` for the private key, both services for the public key) -> **Environment**
  and add the variable, pasting the full PEM including the `-----BEGIN/END ...-----` lines. If the
  input flattens newlines, replace each line break with a literal `\n` - the API converts `\n`/`\r\n`
  back (`kk/config.py::_pem_from_env`, `test_pem_with_escaped_newlines_is_accepted`) and admin-web
  strips them (`spkiBytesFromPem`, `test_f19_verify_admin_jwt.mjs`: "PEM with literal \n").
* Saving a change redeploys/restarts the service. A malformed value makes the API fail to boot, so
  change it only inside a window where you can fix or revert it.
* Never commit the values. `render.yaml` intentionally has no literal value for any `ADMIN_JWT_*` key.
* After pasting, delete the local `.pem` files (or keep only the private key in the secret store).
  Shell history: do not type the PEM on a command line.

### Rotation (and what "overlap" means here)

The code has **a single active admin key**: the API holds exactly one private key and verifies with
exactly one public key; admin-web holds exactly one public key. There is no multi-key (`kid`) support,
so two ES256 keys can **not** be accepted side by side. Rotating therefore invalidates every ES256
admin session: all dashboard admins have to log in again. User sessions (HS256) are not affected.

Procedure (planned rotation, or after a suspected private-key leak):

1. Generate the new pair (above). Keep the old private key in the secret store until step 6.
2. Announce a short window to admins (everyone will be logged out of the dashboard).
3. Set the new `ADMIN_JWT_PUBLIC_KEY` on `carr-admin` and the new `ADMIN_JWT_PRIVATE_KEY` (and
   `ADMIN_JWT_PUBLIC_KEY` if you set it explicitly - it must be the matching one, otherwise the API
   refuses to boot) on `carr`. Do both back to back: between the two deploys old cookies fail the
   edge check and new tokens fail it too, so admins bounce to the login page. Order inside the window:
   admin-web first, then the API (the API restart is what invalidates the old tokens).
   `ADMIN_JWT_ENFORCE` can stay `1` throughout.
4. Admins log in again (new ES256 pair) - verify with the stage checks below.
5. The overlap you do have: the old private key stays in the secret store, so you can revert both
   services to the old pair if the new one misbehaves (sessions minted under the new key then also
   have to log in again).
6. After a stable day, destroy the old private key. If the rotation was caused by a leak, rotate
   first, destroy afterwards, and also consider `JWT_SECRET_KEY` separately (rotating that logs out
   **all** users and is outside this feature).

A true zero-downtime rotation would need multi-key verification in `kk/admin_tokens.py` and
`verify-admin-jwt.ts`; that is not implemented and not required for the launch.

## Acceptance / rejection matrix

Route classes: **A** = admin routes (`/api/admin/*`), e.g. `GET /api/admin/users`; **S** = dashboard
session routes (`/api/auth/me`, `/api/auth/refresh`, `/api/auth/logout`); **U** = every other
authenticated route, e.g. `GET /api/user/favorites`.
States: **N** = no `ADMIN_JWT_*` env (default, launch state); **K** = keys set, `ADMIN_JWT_ENFORCE`
unset (dual mode); **E** = keys set and `ADMIN_JWT_ENFORCE=1`.
Cells are HTTP statuses. "tests" are in `kk/tests/test_f19_admin_token_separation.py`.

### API

| Token kind | State N | State K (dual) | State E (enforce) | Tests |
| --- | --- | --- | --- | --- |
| Legacy HS256 **user** token (no admin claims; also a mobile-login token of an `is_admin` user, `auth_method` claim) | A 403, S ok, U 200 | A 403, S ok, U 200 | A 403, S ok, U 200 | `test_flag_off_user_and_legacy_admin_tokens_work_es256_rejected`, `test_dual_user_login_and_tokens_stay_hs256_and_never_admin`, `test_enforce_user_tokens_and_admin_signed_tokens_work` |
| Legacy HS256 **admin-claim** token (`is_admin` and/or `account_scope=admin`, signed with the real `JWT_SECRET_KEY`) | A 200, S ok, U accepted (decode does not restrict HS256 by route) | A 200, S ok; a refresh with it re-issues an **ES256** pair (code path in `/api/auth/refresh`) | **A 401, S 401 (incl. `/api/auth/refresh`), U 401**; a token with only one of the two claims is 401 too | `test_flag_off_legacy_dashboard_login_and_admin_route_unchanged`, `test_dual_legacy_hs256_admin_token_still_accepted_during_migration`, `test_enforce_rejects_hs256_tokens_with_admin_claims_everywhere`, `test_enforce_forged_legacy_admin_refresh_cannot_mint_admin_session` |
| **ES256 admin** token (issued at dashboard login/refresh; `account_scope=admin` + `is_admin`) | 401 everywhere (ES256 is not a decodable algorithm) | A 200, S 200 (`/api/auth/me`, refresh with the refresh token), **U 401** | same as K | `test_flag_off_user_and_legacy_admin_tokens_work_es256_rejected` (last assert), `test_dual_dashboard_login_issues_admin_signed_tokens_and_refresh_works`, `test_dual_admin_signed_token_accepted_only_on_admin_routes`, `test_enforce_dashboard_login_and_refresh_still_work` |
| **ES256 without admin scope** (valid signature, no claims, or only `is_admin`) | 401 | 401 on A, S and U | 401 on A, S and U (same code path) | `test_dual_es256_without_admin_scope_rejected_even_if_validly_signed` |
| **Refresh token used as access token** | 401 (or 422, see note) | same status as the legacy HS256 refresh-as-access | 401 | `test_dual_refresh_token_cannot_be_used_as_access_on_admin_route` |
| **Expired** (ES256 or HS256) | 401 `Token has expired` | 401 | 401 | ES256: `test_dual_expired_admin_token_rejected`; HS256: stock `expired_token_loader` in `kk/routes/auth.py` (not F-19 specific) |
| **Forged**: ES256 signed with another key | 401 | 401 | 401 | `test_dual_token_signed_by_wrong_key_rejected` |
| **Forged**: HS256 with a wrong secret, `alg: none`, tampered payload, header downgraded ES256->HS256 | 401 | 401 | 401 | `test_dual_wrong_hs256_secret_and_none_alg_and_tamper_rejected` |
| **Forged**: HS256 "signed" with the public key (alg confusion) | 401 | 401 | 401 | `test_dual_alg_confusion_hs256_signed_with_public_key_rejected` |
| **Forged with a leaked `JWT_SECRET_KEY`**: HS256 token with admin claims | **200 on A** (this is the F-19 weakness) | **200 on A** (still the weakness until enforce) | **401** (closed) | `test_enforce_forged_legacy_admin_refresh_cannot_mint_admin_session` |
| Revoked `jti`, inactive user, `tokens_invalid_before` | 401 (unchanged) | 401 | 401 | `test_dual_revocation_and_inactive_user_still_enforced_for_admin_tokens` |

Notes:

* The status of "refresh as access" is whatever the app's JWT error handling returns for a wrong
  token type (the existing suite accepts 401 or 422); the F-19 hook does not touch the type check, so
  an ES256 refresh token gets exactly the status an HS256 refresh token gets.
* Replicas that hold only `ADMIN_JWT_PUBLIC_KEY` verify ES256 tokens but can never issue one
  (`test_public_key_only_verifies_but_cannot_issue`); a private key alone derives the public key
  (`test_private_key_only_derives_public_key`).
* Forged *user* tokens are outside the scope of F-19: anybody holding the API's `JWT_SECRET_KEY` can
  still mint ordinary user tokens in every state.

### admin-web edge check (`verifyAdminAccessJwt`)

Configurations: **S** = only `JWT_SECRET_KEY` (legacy), **S+P** = secret and `ADMIN_JWT_PUBLIC_KEY`
(dual), **P** = only the public key (migrated), **none** = neither.

| Cookie token | S | S+P | P | none |
| --- | --- | --- | --- | --- |
| ES256 admin token, valid | rejected (`no_public_key`) -> refresh rotation | accepted | accepted | production: fail closed (no session); non-production: rejected |
| HS256 admin-claim token, valid signature | accepted | accepted | rejected (`hs256_unverifiable`) -> refresh rotation | production: fail closed; non-production: structure + `exp` only |
| HS256 user token (no admin claims) | rejected (`not_admin`) | rejected | rejected | rejected |
| ES256 without `account_scope=admin` | rejected (`not_admin`) | rejected | rejected | rejected |
| Refresh token in the access cookie (`type != access`) | rejected (`type`) | rejected | rejected | rejected |
| Expired | rejected (`expired`) | rejected | rejected | rejected |
| Wrong key / tampered / truncated or DER signature / forged HS256 | rejected (`signature`) | rejected | rejected | rejected |
| `alg: none` or any unknown alg | rejected (`alg`) | rejected | rejected | rejected |

Tests: `admin-web/scripts/test_f19_verify_admin_jwt.mjs` ("ES256: valid admin token verifies with ONLY
the public key", "ES256: wrong key, tampered payload, truncated/DER signature, expired, not admin are
rejected", "ES256 without a configured public key is never trusted", "migrated state (public key, no
secret): HS256 tokens ... are rejected", "alg=none / unknown algs are rejected in every
configuration", "legacy HS256 behaviour is unchanged when only JWT_SECRET_KEY is configured",
"production with ONLY the public key ...", "production with NEITHER secret nor public key fails
closed", "production legacy (secret only) still works; dual (secret + public key) accepts both");
run with `npm run test:unit` in `admin-web/`.

## Staged roll-out (every step is reversible)

Nothing below is done in production until the policy gate at the top is lifted. **Rehearse the whole
sequence on staging first** (own API + admin-web services, own database, own `JWT_SECRET_KEY`, own
key pair - never reuse production keys on staging).

Verification commands for each stage are in "Verification commands" below.

**Stage 0 - deploy the code, no env change** (current state at launch).
* Preconditions: base contains `02a3185` (it does at `1aab2ef`); `/health` OK after deploy.
* Check: dashboard login works; the access token header says `alg: HS256`; `/api/admin/users` 200 with
  it; user token on `/api/admin/users` 403.

**Stage 1a - give admin-web the public key first.** Set `ADMIN_JWT_PUBLIC_KEY` on `carr-admin`
(keep `JWT_SECRET_KEY` there) and redeploy it.
* Why first: admin-web with secret + public key accepts both HS256 and ES256 (table above), and no ES256
  token exists yet, so this is invisible. (The earlier text of this document set the API first and
  asked to follow with admin-web "immediately", because an ES256 cookie fails the edge check until
  admin-web knows the public key and then churns through refresh rotations.)
* Check: admin dashboard still loads with a legacy login; no new 401s.

**Stage 1b - turn on issuance on the API.** Set `ADMIN_JWT_PRIVATE_KEY` (and optionally
`ADMIN_JWT_PUBLIC_KEY`) on `carr`. **Do not set `ADMIN_JWT_ENFORCE`.** Redeploy.
* Preconditions: stage 1a done; keys validated locally with the validator above and on staging; a
  window in which a failed boot can be reverted (remove the variables).
* Check (dual mode): API boots; a new dashboard login returns **ES256** access and refresh tokens;
  ES256 on `/api/admin/users` 200 and on `/api/auth/me` 200; ES256 on `/api/user/favorites` **401**;
  user login still HS256 and user routes 200; a legacy HS256 admin token captured before the deploy
  still gets 200 on `/api/admin/users`.

**Stage 2 - verify through the real dashboard.** Log in at admin-web, click through the main pages,
wait for the access token to expire (default 30 min) and confirm the silent refresh keeps the session.
* Check: the `carzo_admin_jwt` cookie decodes to `alg: ES256`; no refresh storms in the admin-web logs.

**Stage 3a - remove the shared secret from admin-web.** Optionally wait one refresh lifetime
(`JWT_REFRESH_TOKEN_DAYS`, default 30 days; admin sessions that stay active are migrated to ES256 by
the first refresh anyway - sessions still on legacy HS256 tokens must log in again afterwards). Then
delete `JWT_SECRET_KEY` from `carr-admin` and redeploy it.
* Preconditions: stage 2 passed; `ADMIN_JWT_PUBLIC_KEY` present on `carr-admin`; stage checks pass
  on staging in exactly this configuration.
* Check: dashboard login and navigation still work; a forged HS256 cookie is rejected by admin-web
  (401 via `/backend-api`); `carr-admin` no longer lists `JWT_SECRET_KEY`.

**Stage 3b - enforce on the API.** Set `ADMIN_JWT_ENFORCE=1` on `carr` and redeploy.
* Preconditions: stage 3a done and stable; the private key is on the **same** service as the enforce
  flag (otherwise the API refuses to boot); the pre-launch checklist below is complete.
* Check (enforce mode): HS256 admin-claim token (staging-minted) on `/api/admin/users`, `/api/auth/me`,
  `/api/user/favorites` and `/api/auth/refresh` -> all **401**; ES256 admin token on admin routes
  200, on user routes 401; user token on admin routes 403, on user routes 200; dashboard login,
  refresh and logout work.

From here a compromised admin-web holds nothing that can sign a token.

Splitting the former "stage 3" into 3a and 3b makes each half separately reversible; the end state is
the same as before.

## Verification commands

Placeholders only: `<...>` values are supplied by the operator; no real hosts, tokens or secrets are
stored in this repository. Run these against **staging** (see the forged-token step), and only the
read-only ones (no forging) against production once the feature is deliberately enabled there.

```
API=https://<api-host>             # carr (staging first)
ADMIN=https://<admin-web-host>     # carr-admin

# 1. dashboard login -> access_token / refresh_token  (do not paste the password into shell history)
curl -sS -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"username":"<admin-username>","password":"<admin-password>","account_scope":"admin"}'
ADMIN_ACCESS=<access_token from step 1>;  ADMIN_REFRESH=<refresh_token from step 1>

# 2. ordinary user login (not dashboard)
curl -sS -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d '{"username":"<normal-user-username-or-phone>","password":"<user-password>"}'
USER_ACCESS=<access_token from step 2>

# 3. which algorithm signed a token (header only, no secret needed)
python -c "import sys,base64,json; t=sys.argv[1].split('.')[0]; print(json.loads(base64.urlsafe_b64decode(t+'='*(-len(t)%4)))['alg'])" "$ADMIN_ACCESS"

# helper: print only the HTTP status
code() { curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $1" "$API$2"; }
code "$ADMIN_ACCESS" /api/admin/users
code "$ADMIN_ACCESS" /api/auth/me
code "$ADMIN_ACCESS" /api/user/favorites
code "$USER_ACCESS"  /api/admin/users
code "$USER_ACCESS"  /api/user/favorites
code ""              /api/admin/users
```

PowerShell equivalent of the helper (use `curl.exe`, not the `curl` alias):

```
function code($tok, $path) { curl.exe -s -o NUL -w "%{http_code}`n" -H "Authorization: Bearer $tok" "$env:API$path" }
```

Expected results by state (rows use the tokens above):

| Check | State N (stage 0) | State K (stages 1b-3a) | State E (stage 3b) |
| --- | --- | --- | --- |
| `alg` of `ADMIN_ACCESS` | HS256 | **ES256** | **ES256** |
| `ADMIN_ACCESS` on `/api/admin/users` | 200 | 200 | 200 |
| `ADMIN_ACCESS` on `/api/auth/me` | 200 | 200 | 200 |
| `ADMIN_ACCESS` on `/api/user/favorites` | 200 | **401** | **401** |
| `USER_ACCESS` on `/api/admin/users` | **403** | **403** | **403** |
| `USER_ACCESS` on `/api/user/favorites` | 200 | 200 | 200 |
| no token on `/api/admin/users` | 401 | 401 | 401 |

Refresh rotation and logout (single use: the refresh token is revoked when used):

```
curl -sS -X POST "$API/api/auth/refresh" -H "Authorization: Bearer $ADMIN_REFRESH"        # 200, new pair, same alg as the stage expects
curl -sS -X POST "$API/api/auth/refresh" -H "Authorization: Bearer $ADMIN_REFRESH"        # 401 (already revoked)
code "$ADMIN_REFRESH" /api/admin/users                                                    # refresh token as access token: 401 (or 422)
curl -sS -X POST "$API/api/auth/refresh" -H "Authorization: Bearer $ADMIN_ACCESS"         # access token as refresh token: rejected (4xx)
```

Forged-token check (**staging only**, needs the staging `JWT_SECRET_KEY` in the environment; the
secret is read from the variable and never printed). Expected: state N/K -> `200`
(that is the weakness), state E -> `401`.

```
export STAGING_JWT_SECRET=<staging JWT_SECRET_KEY>          # PowerShell: $env:STAGING_JWT_SECRET = "<...>"
python - <<'PY'
import os, time, uuid, jwt
now = int(time.time())
print(jwt.encode({"sub": "<staging-admin-public_id>", "type": "access", "fresh": False,
                  "jti": str(uuid.uuid4()), "iat": now, "nbf": now, "exp": now + 600,
                  "is_admin": True, "account_scope": "admin"},
                 os.environ["STAGING_JWT_SECRET"], algorithm="HS256"))
PY
FORGED=<printed token>
code "$FORGED" /api/admin/users          # N/K: 200   E: 401
code "$FORGED" /api/user/favorites       # E: 401
curl -sS -X POST "$API/api/auth/refresh" -H "Authorization: Bearer $FORGED"   # E: 401 (access token, rejected either way)
```

(`<staging-admin-public_id>` is the `public_id` of a staging dashboard principal, e.g. from
`GET /api/auth/me` with `ADMIN_ACCESS`. A "no PowerShell heredoc" variant: save the Python body to a
temp file outside the repo and run `python <file>`.)

admin-web checks (same-origin requests only; cookie names `carzo_admin_jwt` / `carzo_admin_refresh`):

```
# forged / garbage cookie must not reach the API: 401
curl -s -o /dev/null -w '%{http_code}\n' -H "Cookie: carzo_admin_jwt=<FORGED or any bad token>" "$ADMIN/backend-api/api/admin/users"
# cross-site state-changing request is blocked: 403 "Cross-site request blocked"
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Origin: https://evil.example" -H "Content-Type: application/json" \
  -d '{"username":"x","password":"y"}' "$ADMIN/api/admin-session"
# security headers on a proxied response (after a real login in a browser, or with a valid cookie)
curl -sI -H "Cookie: carzo_admin_jwt=<ADMIN_ACCESS>" "$ADMIN/backend-api/api/admin/users" | grep -i -E 'x-content-type-options|content-security-policy|cache-control'
```

Key/boot checks: after each deploy the `carr` log must show a normal boot (no `ADMIN_JWT_...`
`RuntimeError`) and `GET $API/health` must be healthy.

## Rollback

Reverse the enabling order: **enforce flag first, then the keys, never the other way round** (keys
removed while `ADMIN_JWT_ENFORCE=1` is set = the API cannot boot).

| Rollback step | When | Effect on live sessions |
| --- | --- | --- |
| R1. Unset `ADMIN_JWT_ENFORCE` on `carr`, redeploy | from stage 3b | No session is invalidated. ES256 sessions keep working. HS256 admin-claim tokens are accepted again (re-opens the leaked-secret path - do this only to recover). |
| R2. Re-add `JWT_SECRET_KEY` to `carr-admin` (same value as the API), redeploy | from stage 3a | No session is invalidated; admin-web verifies HS256 and ES256 again. **Required before R3**, otherwise the HS256 cookie issued by the rolled-back API is rejected by admin-web (`hs256_unverifiable`) and the dashboard loops back to the login page. |
| R3. Unset `ADMIN_JWT_PRIVATE_KEY` (and `ADMIN_JWT_PUBLIC_KEY`) on `carr`, redeploy | from stage 1b/2, after R1 and R2 | **Every ES256 admin access and refresh token stops verifying (401): all dashboard admins must log in again** and then receive HS256 tokens (back to legacy). User sessions are not touched. |
| R4. Unset `ADMIN_JWT_PUBLIC_KEY` on `carr-admin` | optional, after R3 | None beyond R3 (cookies are ES256 or invalid by then). |
| Code rollback (redeploy a release without F-19) | emergency | `ADMIN_JWT_*` variables are simply ignored; same effect as R3; keep `JWT_SECRET_KEY` on `carr-admin`. |

User tokens are unaffected by every step because they never change algorithm or key.
`JWT_SECRET_KEY` stays on `carr-admin` until stage 3a and must be re-added there before any API-side
rollback that returns admin sessions to HS256.

If the private key is lost (but not leaked): R1-R3 and generate a fresh pair later; if it is
**leaked**: rotate (see above) immediately instead of rolling back.

## Pre-launch checklist - admin/user token boundary (staging)

**The admin/user token boundary MUST be verified in staging before public launch**, regardless of
whether F-19 stays disabled at launch. Record date, commit SHA, environment and the person who ran it.

Mode L (legacy, the launch default - F-19 disabled), on a staging copy of the exact release:

* [ ] `USER_ACCESS` (normal user) on `/api/admin/users` -> 403; no token -> 401.
* [ ] A mobile/OTP/password token of a user that has `is_admin=true` (no dashboard login) on
      `/api/admin/users` -> 403 (admin scope is minted only by dashboard login, ADM-1).
* [ ] A dashboard login (`account_scope: admin`) works only with the `AdminAccount` credentials, and
      the same principal user cannot use the mobile password login.
* [ ] A refresh with a mobile token never returns an admin-scoped token; a refresh token is rejected
      as an access token; an access token is rejected at `/api/auth/refresh`.
* [ ] After logout the access token returns 401; `tokens_invalid_before` after a password change
      returns 401 for older tokens.
* [ ] admin-web: bad/forged cookie -> 401 through `/backend-api`; cross-site POST -> 403; security
      headers present (commands above).
* [ ] `carr-admin` has `JWT_SECRET_KEY` (legacy) **or** `ADMIN_JWT_PUBLIC_KEY`; production would fail
      closed if neither were set.

Mode E (before F-19 is ever enabled in production), on staging with its own key pair:

* [ ] Stages 0 -> 1a -> 1b -> 2 -> 3a -> 3b executed with the stage checks above, all rows of the
      expected-results table matched.
* [ ] Forged HS256 admin token: 200 before 3b, 401 after 3b (staging-minted).
* [ ] Rollbacks R1, R2, R3 rehearsed once; admins confirmed they could log in afterwards.
* [ ] Key rotation rehearsed once (all admins logged out, new login works).
* [ ] `ADMIN_JWT_ENFORCE=1` with the private key removed was confirmed to refuse to boot (so nobody is
      surprised in an incident).
* [ ] Production values (private key, public key) exist only in the secret store and the Render
      dashboard; not in git (`git log -p -S "BEGIN PRIVATE KEY"` shows nothing), chat or tickets.
* [ ] Automated tests green on the release commit: `python -m pytest kk/tests/test_f19_admin_token_separation.py`
      and, in `admin-web/`, `npm run test:unit`.
* [ ] Owner sign-off recorded to lift the "F-19 disabled" gate for production.

Note: `docs/DEPLOY_ENV_CHECKLIST.md` still describes `JWT_SECRET_KEY` on `carr-admin` as required; that
is correct only until stage 3a.

## admin-web CSRF / headers

* **Origin check** (`admin-web/src/lib/origin-guard.ts`): `POST/PUT/PATCH/DELETE` to `/backend-api/*`
  and `/api/admin-session` need an `Origin` (or `Referer` fallback) equal to the allowed origin;
  otherwise 403 `Cross-site request blocked` and nothing is forwarded. Default allowed origin = the
  request's own origin (`X-Forwarded-Host`/`Host`, scheme from `X-Forwarded-Proto`). Set
  `ADMIN_ALLOWED_ORIGINS` (comma-separated exact origins) to replace it. `GET/HEAD/OPTIONS` are untouched.
* **Cookies**: `HttpOnly`, `Secure` (per request scheme), `SameSite=Lax`. `Strict` was rejected on
  purpose: external links (chat, e-mail) to the dashboard would otherwise always bounce through the
  login page. Lax + the Origin check blocks the cross-site POST path.
* **Headers**: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy`, `Permissions-Policy` on **all** responses (pages, API routes, the proxy, static
  files); HSTS `max-age=31536000; includeSubDomains` in production only (no `preload`; scoped to the
  admin host's own subdomains, never the shared `onrender.com` parent). Proxied responses additionally
  get `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; sandbox` and a default
  `Cache-Control: private, no-store`; only `content-type`, `cache-control`, `etag`, `last-modified`
  are forwarded (no upstream `Set-Cookie`, no hop-by-hop headers).
* **CSP**: production `script-src 'self' 'nonce-<per request>' 'strict-dynamic'` - no
  `'unsafe-inline'`/`'unsafe-eval'`. Requires dynamic rendering of pages (`dynamic = "force-dynamic"`
  in the root layout); development keeps `'unsafe-inline' 'unsafe-eval'` for HMR.
* **CSV export**: cells starting with `= + - @ TAB CR LF` (also after leading spaces) are prefixed with
  `'`; plain decimal numbers (`-12`, `3.5`) stay unchanged; `+964...` phone numbers are text and get the
  prefix (spreadsheets show a leading `'`).
