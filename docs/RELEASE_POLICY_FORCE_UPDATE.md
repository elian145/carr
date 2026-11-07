# Release policy: force-update (version floors)

Owner policy for the initial public release of CarNet, verified against the code of base `1aab2ef`
(Draft PR #35 head). Where this document and an older document disagree, this document wins; the
older ones are listed in "Documents that still show MIN_* examples" at the end.

## Policy (owner decisions)

1. **The mandatory floors stay UNSET for the initial release.** That means: `min_app_version`,
   `min_android_build`, `min_ios_build` (admin Settings / API) **and** their environment fallbacks
   `MIN_APP_VERSION`, `MIN_ANDROID_BUILD`, `MIN_IOS_BUILD` on the Render `carr` service are all
   empty/absent. With all three empty no client can ever be hard-blocked
   (`test_defaults_mean_no_gate`).
2. **Whenever any floor is used, a valid `latest_app_version` (env `LATEST_APP_VERSION`) must be set**
   to the exact `version` string of the newest release that is live in the stores.
3. **Never activate an iOS hard floor without a working App Store URL** (`ios_store_url`). The code
   does *not* enforce this for you (see "iOS store URL"); it is an operator rule.
4. **Server-side version enforcement (`X-App-Version` / HTTP 426) is deferred until after v1.** Today
   the server only logs the header (see "Deferred").
5. A hard floor is for security-critical or contract-incompatible versions only; everything else is a
   soft prompt (`recommended_*`). `docs/ROLLBACK.md` rule stays: never raise a floor while only a bad
   build is current.

## What exists (verified)

### Server

* `GET /api/config/app` (`kk/routes/misc.py::app_config`, unauthenticated, `Accept-Language`-aware
  messages) returns: `min_app_version`, `min_android_build`, `min_ios_build`, `force_update_message`,
  `recommended_app_version`, `recommended_android_build`, `recommended_ios_build`,
  `latest_app_version` (additive), `soft_update_message`, `android_store_url`, `ios_store_url`,
  `listing_require_approval`, `feature_flags`. Versions are strings (`""` = unset), builds are
  integers or `null`.
* Setting names (`kk/app_settings.py::SETTING_KEYS`) and their env fallbacks:

  | Setting (admin Settings / `PUT /api/admin/settings`) | Env fallback | Default |
  | --- | --- | --- |
  | `min_app_version` | `MIN_APP_VERSION` | empty (no floor) |
  | `min_android_build` | `MIN_ANDROID_BUILD` | empty |
  | `min_ios_build` | `MIN_IOS_BUILD` | empty |
  | `force_update_message` (+ `_ar`, `_ku`) | `FORCE_UPDATE_MESSAGE` (+ `_AR`, `_KU`) | "Please update CarNet to continue." |
  | `recommended_app_version` | `RECOMMENDED_APP_VERSION` | empty |
  | `recommended_android_build` / `recommended_ios_build` | `RECOMMENDED_ANDROID_BUILD` / `RECOMMENDED_IOS_BUILD` | empty |
  | `latest_app_version` | `LATEST_APP_VERSION` | empty |
  | `soft_update_message` (+ `_ar`, `_ku`) | `SOFT_UPDATE_MESSAGE` (+ `_AR`, `_KU`) | "A newer version of CarNet is available." |
  | `android_store_url` | `ANDROID_STORE_URL` | `https://play.google.com/store/apps/details?id=com.carnetiq.app` |
  | `ios_store_url` | `IOS_STORE_URL` | **empty** |

* **Precedence** (`get_platform_settings`): a non-empty admin (database) value wins; otherwise the env
  value; otherwise the default above.

### Client

* `lib/services/app_version_gate.dart` (`AppVersionGate.evaluate`) and
  `lib/app/widgets/force_update_gate.dart` (blocking screen + soft prompt).
* Hard block when the installed version is below `min_app_version` **or** the installed build number
  is below the platform's floor (`min_android_build` on Android, `min_ios_build` on iOS; `0`/unset =
  no floor). `min_app_version` applies to **both** platforms. A device already on or above
  `latest_app_version` is never hard-blocked ("latest-aware escape").
* Soft prompt (dismissible, remembered per recommendation) below `recommended_*`.
* The blocking screen has "Update now" **only when a valid store URL exists**, and "Try again".

## Accepted values and caps

Server write validation (`update_platform_settings`, `PUT|PATCH /api/admin/settings`; a bad value is a
`400` `{"message": ..., "field": ...}` and **nothing** is stored) and the mirrored client/read-side
parsers:

| Field | Accepted | Rejected (examples) |
| --- | --- | --- |
| `min_app_version`, `recommended_app_version`, `latest_app_version` | real string `N[.N[.N[.N]]]`, 1-4 ASCII digits per part, **major <= 99**; stored in canonical form (`01.02` -> `1.2`); `0.0.0` and `99.0.0` are valid | `v2.0.0`, `1.x`, `1..2`, `-1.0.0`, `1.0.0-beta`, `1.0.0+7`, `100.0.0`, `999.0.0`, five parts, non-ASCII digits, JSON numbers/lists/bools (`test_parse_version_accepts`, `test_parse_version_rejects`) |
| `min_android_build`, `recommended_android_build` | whole number 0 .. 2,100,000,000 | negatives, floats, `+5`, text, bools (`test_parse_build_number_bounds`) |
| `min_ios_build`, `recommended_ios_build` | whole number 0 .. 999,999,999,999,999,999 | same |
| `android_store_url`, `ios_store_url` | absolute URL, scheme `http`/`https`/`market`/`itms-apps`/`itms-appss`, host present, no whitespace, <= 2048 chars | `javascript:`, `ftp:`, relative or space-containing URLs (`test_sanitize_store_url`) |
| cross-check | `min_app_version` may **not** be above `latest_app_version` (400, also when lowering `latest` below the stored floor) | `test_floor_above_latest_is_rejected`; a floor without `latest` is allowed (`test_floor_without_latest_is_allowed`) |

Empty string or `null` clears an override (`test_empty_and_null_clear_the_override`).

Read-side safety net (what `/api/config/app` serves even if something bad is already stored, via the
database or env): an unparsable/over-cap floor is served as unset, a floor above a valid
`latest_app_version` is served as unset, an invalid build is `null`, an invalid store URL is `""` (and
the Android URL falls back to the default Play URL) - `test_bad_stored_floor_is_served_as_unset`,
`test_stored_floor_above_stored_latest_is_served_as_unset`, `test_env_default_floor_is_also_sanitised`.
The client applies the same rules again (`AppVersionRequirement.fromJson`, `maxVersionMajor = 99`).

Caveat that follows from the cross-check: it only protects you when `latest_app_version` is set **and
correct**. A `latest_app_version` that is *higher* than what is actually live lets you set a floor no
store can satisfy. Set `latest_app_version` to the exact published version, update it **before** raising
a floor for a new release, and never to a version that is still in review or in a staged rollout.

## Setting values (and the env-fallback gotcha)

* Admin Settings page (`admin-web/src/app/settings/page.tsx`, section "App update gates"): fields for
  min app version, force-update message, min Android/iOS build, recommended app version, soft message,
  recommended Android/iOS build, Android/iOS store URL. A server `400` is shown as a toast with the
  server's message.
  * There is **no field for `latest_app_version`** and none for the `_ar`/`_ku` message overrides.
    Set them through the API (`PUT /api/admin/settings` with an admin access token, body e.g.
    `{"latest_app_version": "1.0.0"}`) or the `LATEST_APP_VERSION` env var. The page never sends
    `latest_app_version`, so saving the page does not touch it.
  * **Save writes every field of the form.** The form is pre-filled from the *effective* values, so a
    Save (even for an unrelated change) stores env-derived values - including the default Android store
    URL and any `MIN_*` env value - as database overrides from then on.
  * "Reset to env defaults" sends an empty value for all of the fields shown, which removes the
    overrides.
* **Env-fallback gotcha:** clearing an admin value (empty string / `null` / "Reset to env defaults")
  does **not** disable the floor if the matching `MIN_*` env var is set on Render: the empty override
  disappears and the env value takes over (`get_platform_settings`). Therefore **leave `MIN_APP_VERSION`,
  `MIN_ANDROID_BUILD`, `MIN_IOS_BUILD` unset in the Render dashboard** and only ever use the admin
  settings for floors. A bad env value is still sanitised on read (see above) but a *valid* one stays
  in force until the env var is removed (which needs a service restart).
* If an env floor is ever in force and cannot be removed quickly, set an explicit non-empty "no gate"
  override instead: `min_app_version = "0.0.0"` (valid, and every installed version satisfies it) and
  `min_android_build = "0"` / `min_ios_build = "0"` (the client treats `0` as no floor).

## Store URLs

* **Android:** the server falls back to `https://play.google.com/store/apps/details?id=com.carnetiq.app`
  when `android_store_url` is empty or invalid (prod flavor `applicationId` is `com.carnetiq.app`,
  `android/app/build.gradle.kts`). The Play listing must exist before any Android floor.
* **iOS store URL:** `ios_store_url` has **no default**; empty or invalid is served as `""`. The format
  is `https://apps.apple.com/app/id<numeric Apple ID>` (the Apple ID comes from App Store Connect; the
  tests use `https://apps.apple.com/app/id1`; `itms-apps://...` is also accepted).
  **What the code does with a missing URL:** nothing prevents an iOS floor from being activated
  without one - write validation does not look at the store URL, `/api/config/app` serves `""`, and
  the client shows the blocking screen **without "Update now"** (only "Try again"): a dead end for
  every iOS user below the floor. Hence the rule: **never activate `min_app_version` or
  `min_ios_build` (or `recommended_*` you care about) until `ios_store_url` is set to the real,
  already-live App Store URL and has been opened on a real iPhone.**
  (`IOS_APP_STORE_ID` is a different setting: it only feeds the Safari Smart App Banner on share
  pages, `kk/routes/misc.py`.)
* Because `min_app_version` applies to iOS too, an "Android-only" semantic floor does not exist: use
  `min_android_build` for Android-only floors.

## Failure behaviour (fail-open, 24 h stale cap)

(`AppVersionGate`; tests `test/f_fu_app_version_gate_test.dart`, `test/f_fu_force_update_gate_test.dart`)

* A failed fetch (timeout, transport error, non-200, non-JSON, non-object) is **never cached as a
  result**: the gate opens (no block) unless a last known-good requirement exists.
* A last known-good requirement is kept for at most **24 hours** (`staleMax`) while every refetch
  fails; after that the gate is open. With no known-good value (cold start while the API is down) the
  gate is open: a hard floor cannot be enforced while `/api/config/app` is unreachable.
* A successful response is reused for 15 minutes (`cacheTtl`); after a failure the next non-forced
  fetch waits 30 seconds (`failureBackoff`).
* Garbage values are treated as "no floor" (wrong types, over-cap majors, negative builds, a floor
  above `latest_app_version`); an unparsable *installed* version/build never blocks.
* The request goes through `ApiService.getHttp`, which can serve a <= 5 minute old cached 200 body
  when a request times out (`_getWithAdaptiveTimeout`); a floor change can therefore take up to 5
  extra minutes to reach a client on a flaky connection.

## Lifting a bad floor

Goal: unblock users without a new app release.

1. Open admin Settings -> "App update gates" and clear the offending field(s) (`min_app_version`,
   `min_android_build`, `min_ios_build`) -> Save. Or via the API:
   `PUT /api/admin/settings` with `{"min_app_version": "", "min_android_build": "", "min_ios_build": ""}`.
   Takes effect on the next `/api/config/app` request (the server reads the setting on every call).
2. **Check the env fallback:** `MIN_APP_VERSION` / `MIN_ANDROID_BUILD` / `MIN_IOS_BUILD` must be unset on
   `carr`. If one is set, either remove it in the Render dashboard (restart) or use the explicit "no
   gate" values from the section above right away.
3. Verify: `curl -s https://<api-host>/api/config/app` shows `"min_app_version": ""` and `null` builds
   (placeholders; do not run against production without the owner's go-ahead).
4. Blocked users are released without reinstalling: "Try again" does a real refetch, and returning to
   the app re-checks (at least 10 s apart; a blocked user re-checks on every resume). Users who are not
   blocked pick the change up within 15 minutes or at the next cold start.
5. If the floor itself is correct but the store build is bad, do **not** raise it further: ship the
   fixed build first (`docs/ROLLBACK.md`).

## Version formats the installed app reports

* `pubspec.yaml` currently has `version: 1.0.0+7` (name `1.0.0`, build `7`). Android takes both from
  pubspec (the Android workflows pass no `--build-number`). iOS takes the version name from pubspec
  too (the hard-coded `--build-name="1.0.0"` was removed from `codemagic.yaml`,
  `test_no_hardcoded_build_name_in_ios_builds`) but its build number is the last 18 digits of the
  Codemagic build id (`codemagic.yaml`), so `min_ios_build` is not a human-manageable number. Prefer
  `min_app_version` over the build floors, and keep the pubspec version name equal to the version you
  publish.
* The client reads the installed version leniently (leading `N[.N...]`, optional `v`, any `-dev` /
  `+7` suffix ignored; unparsable = never blocked). **The server's floor values are strict** (no
  suffixes), so a floor can never target a pre-release suffix.

### Dev/stage suffix caveat

`dev` and `stage` flavors have `versionNameSuffix` `-dev` / `-stage` and package-id suffixes
(`android/app/build.gradle.kts`). The client ignores the suffix when comparing, so a dev/stage build
that points at an API with a floor is blocked exactly like a production build, and its "Update now"
opens the **production** Play URL (`com.carnetiq.app` by default), which cannot update a dev/stage
install. Use a separate staging API (own settings) for flavor builds, and never raise a floor on the
production API while testers run dev/stage builds against it.

## Admin-web settings page notes (summary)

See "Setting values". In short: no `latest_app_version` or `_ar`/`_ku` fields; Save persists the whole
form (including env-derived values); "Reset to env defaults" falls back to env, so env `MIN_*` must be
unset; 400 messages arrive as a toast.

## Deferred: server-side enforcement (`X-App-Version` / 426) - after v1

Today: the client sends **no** version header (no `X-App-Version` / `X-App-Platform` /
`X-App-Build` in `lib/`), and the server only logs those headers, charset-filtered, on
`GET /api/config/app` (`_log_client_version_headers`: "Diagnostics only ... NOT used for any
decision"; `test_client_version_headers_are_diagnostic_only`). There is no `426` anywhere in `kk/`.
The gate is therefore advisory: a modified or old client that never calls `/api/config/app`, or an API
call from a script, is not blocked.

What enforcement would require (not implemented; decide after v1):

* Client: send `X-App-Version`, `X-App-Build`, `X-App-Platform` on every API call (single injection
  point in the HTTP client wrapper), plus a handler that maps a `426` response to the existing blocking
  screen with the store URL; shipped binaries without the header must keep working (treat "missing
  header" as allowed).
* Server: a `before_request` hook with its own minimum-supported-version setting (separate from the UI
  floors), exempting `/health`, `/api/config/app`, `/.well-known/*`, legal pages and the web handoff
  pages; strict parsing of the header (same grammar as above); a deterministic JSON body for the
  `426`; Socket.IO and upload endpoints considered; CORS allow-headers updated if
  browser clients ever send the header.
* Operations: a kill switch, an audit log entry per change, adoption metrics from the new headers
  before choosing any minimum, and rehearsal on staging with real devices.
* Tests: header missing / malformed / below / equal / above minimum, exempt routes, 426 shape, client
  mapping, plus the existing gate tests unchanged.

## Release-day checklist

Before submitting / releasing:

- [ ] `pubspec.yaml` version name matches the release you are publishing; build number increased.
- [ ] Render `carr` env: `MIN_APP_VERSION`, `MIN_ANDROID_BUILD`, `MIN_IOS_BUILD` **unset**;
      `RECOMMENDED_*` unset unless a soft prompt is intended; `LATEST_APP_VERSION` unset or equal to the
      version that is live; `IOS_STORE_URL` set once the App Store listing exists (not required while no
      floor is used).
- [ ] Admin Settings -> App update gates: min fields empty. (Opening the page and saving is fine; it only
      persists what the form shows.)
- [ ] `curl -s https://<api-host>/api/config/app` (read-only): `min_app_version` `""`, `min_android_build`
      and `min_ios_build` `null`, `android_store_url` the Play URL for `com.carnetiq.app`.
- [ ] Release is live in **both** stores (staged rollout finished) before `latest_app_version` is set to
      it.
- [ ] Rehearsal on staging with real devices before the first floor is ever used: floor above the
      installed version blocks and "Update now" opens the right store page; lowering the floor and
      pressing "Try again" releases; API offline while the app runs fails open; `latest_app_version`
      escape works.
- [ ] `docs/ROLLBACK.md` read; the person who can lower a floor has admin access and knows the env
      fallback gotcha.

Using a floor later (post-v1), only when all hold: security / incompatible-contract reason; fixed
version live to 100 % in both stores; `latest_app_version` set to it; `android_store_url` and
`ios_store_url` verified; value entered is the published **version string**; soft prompt ran for a
period first unless it is an emergency; lowering procedure rehearsed.

## Documents that still show MIN_* examples

These predate the policy and are not changed by this document's commit; treat them as superseded:
`render.yaml` header comment (`MIN_APP_VERSION=1.0.1`, `MIN_ANDROID_BUILD=4`, `MIN_IOS_BUILD=4`; comments
only - no `MIN_*` key is declared as an env var), `kk/.env.example`, and
`docs/DEPLOY_ENV_CHECKLIST.md` ("Optional force-update gates").
