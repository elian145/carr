# F-19: admin token separation and admin-web hardening

Audit F-19: the admin Next.js service held the API's `JWT_SECRET_KEY` (HS256). Compromising
admin-web let an attacker mint a valid token for **any** user. This document describes the
opt-in fix, the staged roll-out and the rollback. Nothing changes until the new env vars are set.

## Design

| Token | Signed by | Verified by | Notes |
| --- | --- | --- | --- |
| User tokens (mobile app, OTP, password) | `JWT_SECRET_KEY`, HS256 | API | unchanged |
| Admin-scoped tokens (`account_scope=admin`, only after `AdminAccount` dashboard login) | `ADMIN_JWT_PRIVATE_KEY`, ES256 (EC P-256) | API (`ADMIN_JWT_PUBLIC_KEY`/derived) and admin-web (`ADMIN_JWT_PUBLIC_KEY`) | admin-web holds a **public** key only |

API side (`kk/admin_tokens.py`, hook in `kk/app_factory.py`, settings in `kk/config.py`):

* An ES256 token is accepted only if the signature verifies with the admin public key, it carries
  `account_scope=admin` + `is_admin`, **and** it is presented to an admin route (`/api/admin/*`) or
  to `/api/auth/me|refresh|logout` (what the dashboard needs). Anywhere else (e.g.
  `/api/user/...`) it is a 401.
* HS256 tokens keep working exactly as before (user tokens) - unless `ADMIN_JWT_ENFORCE=1`, in
  which case an HS256 token carrying admin claims is rejected everywhere (including `/api/auth/refresh`),
  so a leaked `JWT_SECRET_KEY` can no longer produce an admin session.
* `alg` is constrained to `HS256`/`ES256`; the key is chosen per algorithm (HS256 -> only the shared
  secret, ES256 -> only the admin public key), so `none`, RS256 and HS256-signed-with-the-public-key
  confusion attacks are rejected.
* Revocation (`jti` blocklist, inactive users, `tokens_invalid_before`) is unchanged: the admin
  tokens carry the same `jti/iat/sub/type/fresh` claims.

admin-web (`admin-web/src/lib/verify-admin-jwt.ts`, `admin-session-auth.ts`):

* Verifies ES256 with WebCrypto against `ADMIN_JWT_PUBLIC_KEY`. No shared secret needed.
* Production fails closed unless `ADMIN_JWT_PUBLIC_KEY` or the legacy `JWT_SECRET_KEY` is set.
* With the public key set and no secret, HS256 cookies are rejected (cannot be verified).
* admin-web never sees the refresh-token signing key either (refresh tokens are opaque to it and
  are exchanged at the API).

Env vars:

| Var | Service | Meaning |
| --- | --- | --- |
| `ADMIN_JWT_PRIVATE_KEY` | API only | EC P-256 private key, PKCS8 PEM (newlines may be `\n`) |
| `ADMIN_JWT_PUBLIC_KEY` | API (optional, derived) + admin-web | matching SPKI public key PEM |
| `ADMIN_JWT_ENFORCE` | API | `1` = reject HS256 tokens carrying admin claims (needs the key pair) |
| `ADMIN_ALLOWED_ORIGINS` | admin-web (optional) | CSRF allow-list, see below |

Generate a key pair (once, offline):

```
openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8 -nocrypt -out admin_jwt_private.pem
openssl pkey -in admin_jwt_private.pem -pubout -out admin_jwt_public.pem
```

Boot-time validation (API): invalid / non-P-256 / encrypted keys, a public key that does not match
the private key, or `ADMIN_JWT_ENFORCE` without the private key, make the API refuse to start
(`RuntimeError`) instead of silently running with a weaker mode.

## Issuance hunk (kk/routes/auth.py)

`_access_token_for_user` / `_refresh_token_for_user` must call `issue_admin_token(...)` (returns
`None` => legacy HS256). It is a 10-line patch owned by the auth work:
`_agent_logs/batch6/f19/auth_py_hunk.patch`. **Until it is applied the API still issues HS256 admin
tokens even with the keys set** (verification and enforcement of ES256 already work). Do **not**
set `ADMIN_JWT_ENFORCE=1` before the hunk is deployed (admins could not log in).

## Staged roll-out (every step is reversible)

0. Merge/deploy this code (no env change => behaviour identical to before).
1. Generate the key pair. Set `ADMIN_JWT_PRIVATE_KEY` + `ADMIN_JWT_PUBLIC_KEY` on the **API**
   service and deploy the API (with the auth.py hunk). New admin logins/refreshes now get ES256 tokens;
   legacy HS256 admin tokens still work (dual mode). admin-web still has `JWT_SECRET_KEY` and does
   not yet know the public key: its edge check of an ES256 cookie fails, which falls back to a
   refresh rotation; to avoid that churn do step 2 immediately after step 1.
2. Set `ADMIN_JWT_PUBLIC_KEY` on **admin-web** and redeploy it. It verifies ES256 and (while
   `JWT_SECRET_KEY` is still there) legacy HS256.
3. Wait one refresh lifetime (`JWT_REFRESH_TOKEN_DAYS`, default 30 days, or force everyone to
   re-login), then: **remove `JWT_SECRET_KEY` from the admin-web service**, redeploy it, and set
   `ADMIN_JWT_ENFORCE=1` on the API (redeploy). Remaining legacy admin sessions simply have to log in
   again. From here a compromised admin-web holds nothing that can sign a token.
4. Rotation: generate a new pair, repeat steps 1-3 for the new pair (all admin sessions re-login;
   there is a single active admin key).

Rollback:

* From stage 3: unset `ADMIN_JWT_ENFORCE` (API) and re-add `JWT_SECRET_KEY` to admin-web.
* From stage 1/2: unset `ADMIN_JWT_PRIVATE_KEY`/`ADMIN_JWT_PUBLIC_KEY` on the API. Issued ES256
  tokens stop verifying (admins log in again, now getting HS256 tokens); user tokens are unaffected at
  every step. Keep `JWT_SECRET_KEY` on admin-web until you are sure.

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
