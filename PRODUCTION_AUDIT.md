# Production Readiness Audit — CarNet / Carzo

**Repository:** `D:\car listing ap\carr`
**Audit date:** 2026-09-04
**Commit at audit:** `e560a33` ("Harden launch readiness: gate listing contact PII, rate-limit AI, and add Play web delete path")
**App version:** `pubspec.yaml` → `1.0.0+3`
**Method:** Read-only static analysis of every layer, plus live checks (`flutter test`, `flutter analyze`, `pytest kk/tests`, Alembic upgrade run, production host HTTP probes). No code was modified.

---

## 0. VERDICT

**The application is NOT production ready.**

This is not a scaffold — it is a substantial, largely well-engineered codebase (~3 MB of Dart across 436 files, ~600 KB of Python across the `kk/` Flask app, 42 Alembic migrations, a Next.js admin dashboard, and a real CI/CD setup). Many things are done properly and are called out with evidence in §11.

However, there are **11 CRITICAL blockers**, three of which are architectural rather than bugs:

| # | Blocker | One-line |
|---|---|---|
| C-01 | Auth bypass | `POST /api/auth/signup` mints valid JWTs with **no OTP verification and a randomly invented phone number** |
| C-02 | Chat broken | REST image/video sends emit **no socket event and no push** — the recipient never learns a message arrived |
| C-03 | Search unreachable | Backend has full-text search; the Flutter app **never sends the `q` parameter**. There is no keyword search in the product |
| C-04 | Reviews missing | Reviews/ratings **do not exist** in backend, database, or app |
| C-05 | Payments missing | No payment integration of any kind; "featured listings" are an admin-only free flag |
| C-06 | Cannot ship Android | Release AAB **cannot be built** — signing keystore absent and Gradle hard-fails `prodRelease` |
| C-07 | Schema drift | `pending_signup` model has **no migration** — table will not exist on Postgres |
| C-08 | Docker breaks uploads | `.dockerignore` excludes `tools/`, which `kk/r2_ops.py` requires — all R2 uploads fail in the container image |
| C-09 | No test safety net | **43 of 318 Flutter tests fail**; the GitHub CI prod-AAB step is broken; backend `pytest` is not in CI |
| C-10 | Chat media public | Chat attachments are world-readable URLs with **no access control** |
| C-11 | Money as float | Prices stored as SQL `Float`, not `Numeric`/integer cents |

**Do not tell stakeholders the app is complete.** The core browse/sell/chat loop works and is defensible. Keyword search, reviews, and monetization are absent, and the app cannot currently be signed for the Play Store.

**Estimated effort to production:** 4–7 weeks of focused work for Phases 1–2, assuming reviews and payments are descoped from v1 (see §14 Phase 1 decision gate).

---

## 1. ARCHITECTURE MAP

Understanding this is a prerequisite to everything else, because the repo contains **decoy backends**.

```
carr/
├── lib/                    Flutter app (436 .dart files) ← THE app
├── kk/                     Flask + Socket.IO API ← THE REAL BACKEND
│   ├── app_factory.py      create_app(); Socket.IO + Redis message queue
│   ├── models.py           29 SQLAlchemy models
│   ├── routes/             13 blueprints, ~120 endpoints, all WITHOUT url_prefix
│   ├── tasks/              Celery: alerts, image processing, notifications
│   └── wsgi.py             gunicorn entrypoint (kk.wsgi:app)
├── backend/                ⚠️ DECOY — a 10 KB local dev proxy (:5003 → kk:5000). NOT production.
├── admin-web/              Next.js admin dashboard (httpOnly cookie auth)
├── migrations/versions/    42 Alembic revisions, single head `a3b4c5d6e7f8`
├── android/ ios/           Platform config, 3 flavors (dev/stage/prod)
├── test/                   ~101 Flutter test files
├── kk/tests/               12 backend pytest files (53 tests)
└── scripts/                Launch gates: publish_gate, verify_aab_signing, etc.
```

**Deployment:** Render (`render.yaml`) runs `bash start_render.sh` → gunicorn `kk.wsgi:app`; `Procfile` additionally defines `worker` (Celery) and `beat`. Docker (`Dockerfile`) is an alternative path and is **broken for uploads** (C-08).

### Architecture issues

| ID | Sev | Issue | Evidence |
|---|---|---|---|
| A-01 | HIGH | **Decoy backend.** `backend/server.py` + `backend/requirements.txt` are a dev proxy, but `README.md:89-104` presents the `:5003` proxy as the default dev path while production uses `kk/` directly. A new engineer will modify the wrong file. `backend/.env.example` references `BRIGHTER_API_KEY`, read by nothing. | `backend/server.py:29`, `README.md:89-104` |
| A-02 | HIGH | **Three parallel schema paths.** Alembic migrations, `db.create_all()` fallback (`kk/app_factory.py:348-354`), and runtime SQLite `ALTER TABLE` (`kk/legacy_schema.py:4-200`). Dev and prod schemas can silently diverge. | see §6 |
| A-03 | MEDIUM | **No blueprint URL prefixes.** All 13 blueprints register with no prefix, so paths are absolute strings scattered across files. Route collisions are possible and undetectable. | `kk/routes/__init__.py` |
| A-04 | MEDIUM | **Duplicated filter logic.** API filtering is SQL (`kk/routes/cars.py`); saved-search alert matching is Python (`kk/listing_filters.py:car_matches_filters`). They already drift (`engine_type` vs `fuel_type`), so alerts fire for listings that search would not return. | `kk/listing_filters.py` vs `kk/routes/cars.py:547-660` |
| A-05 | MEDIUM | **Two i18n systems.** Generated `AppLocalizations` (803 ARB keys) coexists with ~15 files doing `if (code == 'ar') ... else if (code == 'ku')` inline maps (e.g. `lib/shared/i18n/comparison_strings.dart:5-40`, `lib/shared/trust/report_dialog.dart:28-124`). | see §10 |
| A-06 | LOW | **Orphan singleton.** `lib/services/car_service.dart:7-10` is a `ChangeNotifier` never registered in the provider tree and unused by the home feed. Dead code that looks live. | `lib/services/car_service.dart` |

---

## 2. COMPLETE FEATURE INVENTORY

Classification legend: **COMPLETE** = full path verified UI → state → API → auth → DB → response → UI, including error and empty handling. Nothing is marked COMPLETE without that evidence.

| # | Feature | Status | Evidence / gap |
|---|---|---|---|
| 1 | Flutter frontend | **PARTIALLY COMPLETE** | 436 files, clean architecture, 0 analyzer errors, but 60 analyzer issues and 43 failing tests |
| 2 | Backend | **PARTIALLY COMPLETE** | `kk/` is real and substantial; decoy `backend/` confuses (A-01) |
| 3 | API endpoints | **PARTIALLY COMPLETE** | ~120 endpoints; inconsistent response shapes (§8 B-09); some unbounded |
| 4 | Database models | **PARTIALLY COMPLETE** | 29 models, good indexes; float money (C-11), no ON DELETE policies |
| 5 | Database migrations | **BROKEN** | Single clean head verified by running the chain, **but** `pending_signup` never created (C-07); 3 migrations swallow failures |
| 6 | Authentication | **UNSAFE** | Bcrypt, JWT blocklist, refresh rotation, HMAC-stored OTPs — all good. Undermined by C-01 signup bypass |
| 7 | Authorization | **COMPLETE** | Verified: `_resolve_car_for_user` ownership, `_get_owned_search`, notification `user_id` scoping, 43 `_deny(permission)` RBAC calls in admin. No IDOR found on mutations |
| 8 | User accounts | **PARTIALLY COMPLETE** | Signup/login/reset/delete all present; tokens survive password change (H-01) and account ban (H-02) |
| 9 | Car listings | **COMPLETE** | Create (idempotency-keyed) → moderation `pending` → visibility filter → edit/delete/mark-sold, all ownership-checked. `kk/listing_visibility.py:37-42` applied consistently |
| 10 | Search | **MISSING** | Backend FTS at `kk/routes/cars.py:547` is never called by the app (C-03) |
| 11 | Filters | **PARTIALLY COMPLETE** | ~20 filters map correctly via `homeFiltersToApiQuery`; `damaged_parts` re-filtered client-side; `contactPhone` filter is dead |
| 12 | Favorites | **PARTIALLY COMPLETE** | Full path works; optimistic on cards but not on the Favorites page; N+1 queries; toggle race (M-05) |
| 13 | Profiles | **PARTIALLY COMPLETE** | User + dealer profiles work; public dealer route misses the approval check (H-04); exact GPS exposed (H-05) |
| 14 | Reviews | **MISSING** | No model, no endpoint, no UI, no rating widget anywhere (C-04) |
| 15 | Messaging/chat | **BROKEN** | Socket path works; REST path does not notify recipients (C-02) |
| 16 | Notifications | **PARTIALLY COMPLETE** | In-app list + push work via socket sends only; REST sends create no `Notification` row; list has no error state |
| 17 | Image uploads | **PARTIALLY COMPLETE** | Magic-byte validation, HMAC owner-prefixed R2 keys, path-traversal guards — good. Presigned path unvalidated (H-06); no image count cap |
| 18 | File storage | **PARTIALLY COMPLETE** | R2 with production fail-fast guard (`kk/config.py:100-127`) — good. Broken in Docker (C-08); no orphan cleanup |
| 19 | Payments | **MISSING** | Zero payment code. `docs/PAYMENTS.md` documents this as intentional/off-platform (C-05) |
| 20 | Promotion / featured | **PARTIALLY COMPLETE** | `Car.is_featured` boolean, admin-set, enforced in SQL `ORDER BY`. No expiry, no purchase path |
| 21 | Admin functionality | **COMPLETE** | 40+ endpoints, all `@admin_required` + `_deny(permission)`; super-admin gates on role/purge/settings; cannot self-elevate or delete other admins; audit log via `UserAction` |
| 22 | Reporting / moderation | **PARTIALLY COMPLETE** | Report + queue + resolve work. Reported content stays public; duplicate reports allowed; resolutions not audit-logged; user never told why |
| 23 | Localization | **PARTIALLY COMPLETE** | 803 keys × 3 locales, **0 missing keys** — genuinely good. Undermined by English-only backend strings (§10) |
| 24 | Kurdish | **PARTIALLY COMPLETE** | `ku` with safe Arabic delegate fallback; 6 keys still English; no `ckb` alias in `supportedLocales` |
| 25 | Arabic | **PARTIALLY COMPLETE** | Fully translated; relative-time strings lack ICU plurals |
| 26 | RTL support | **PARTIALLY COMPLETE** | **Zero** `EdgeInsets.only(left:/right:)` in 436 files — excellent. ~15 non-directional back/chevron icons remain |
| 27 | Navigation | **COMPLETE** | Route table `buildProductionRoutes()`, `AuthGuard` on protected routes, deep links, edge-swipe back |
| 28 | State management | **PARTIALLY COMPLETE** | Provider + setState; `mounted` used in ~95 files but missed in several post-await paths |
| 29 | Error handling | **PARTIALLY COMPLETE** | Centralized `ApiException` + `userErrorText()` sanitization. Silent swallows in critical paths (§8) |
| 30 | Loading states | **PARTIALLY COMPLETE** | Skeletons on home/favorites/my-listings; bare spinners elsewhere |
| 31 | Empty states | **COMPLETE** | `EmptyStatePanel` used consistently across all list screens |
| 32 | Offline handling | **PARTIALLY COMPLETE** | Global `ConnectivityBanner`, disk cache + stale-while-revalidate. Wi-Fi-without-internet reads as online; car detail shows "not found" when offline |
| 33 | Security | **UNSAFE** | Strong foundations (see §11) with critical holes C-01, C-10 |
| 34 | Performance | **PARTIALLY COMPLETE** | Good browse indexes and eager loading on `/api/cars`; N+1 on favorites/recently-viewed/analytics; unbounded dealer listings |
| 35 | API validation | **PARTIALLY COMPLETE** | Field allowlists on car update (no mass assignment), pagination clamps. Unbounded saved-search JSON; some `.all()` |
| 36 | Database integrity | **PARTIALLY COMPLETE** | Good composite PKs and dedupe constraints; no ON DELETE policies; orphan rows possible |
| 37 | Logging | **COMPLETE** | Structured JSON logging, request IDs, Sentry, token-prefix-only redaction (`kk/logging_utils.py`) |
| 38 | Environment variables | **PARTIALLY COMPLETE** | `kk/.env.example` is thorough; root `.env.example` is a 20-line stub; `ROBOFLOW_*` and `FEATURE_FLAG_*` undocumented |
| 39 | Android configuration | **BROKEN** | Cannot sign a release AAB (C-06) |
| 40 | iOS configuration | **UNKNOWN — NEEDS MAC** | Complete on paper; `?mode=developer` in prod entitlements; no committed `Podfile.lock`; Maps key empty |
| 41 | Push notifications | **PARTIALLY COMPLETE** | Both platforms wired; backend `/health/push` returns `fcm_ready: true` live. Invalid tokens never cleared; single token per user |
| 42 | Deep links | **COMPLETE (server-verified)** | Live probe: `assetlinks.json` → `com.carzo.app`; AASA → `LN3R46L4H8.com.carzo.app`, paths `/listing/*`. Device tap-to-open still needs manual test |
| 43 | App permissions | **PARTIALLY COMPLETE** | Correct set for the feature set; `mobile_scanner` + `geocoding` declared but unused → store-review risk |
| 44 | Release configuration | **BROKEN** | R8 + shrink enabled and cleartext blocked, but signing blocked (C-06) |
| 45 | Dependencies | **PARTIALLY COMPLETE** | 38 direct Flutter deps; 6 Python deps unpinned; `video_thumbnail ^0.5.3` maintenance risk |
| 46 | Tests | **NOT PRODUCTION READY** | 43 failures; no token-refresh, offline, RTL, or E2E-sell test (C-09) |

---

## 3. CRITICAL FINDINGS (C-01 … C-11)

### C-01 — Signup creates authenticated accounts with no phone verification

- **Severity:** CRITICAL · **Feature:** Authentication
- **File:** `kk/routes/auth.py`, lines **1698–1766** · **Function:** `compat_signup()` (route `POST /api/auth/signup`, line 1596)
- **Problem:** `compat_signup` has two branches. The OTP branch (1620–1697) correctly verifies a code. Execution then falls through to a second branch that requires **only a password**. If no phone is supplied it **invents one**:

```python
# kk/routes/auth.py:1698-1699
if not phone_digits:
    phone_digits = f"070{secrets.randbelow(10**8):08d}"
```

It then creates the user and immediately issues both tokens:

```python
# kk/routes/auth.py:1750-1766
user.set_password(password)
db.session.add(user)
db.session.commit()
access_token = _access_token_for_user(user)
refresh_token = _refresh_token_for_user(user)
return jsonify({"message": "Signup successful", "token": access_token,
                "access_token": access_token, "refresh_token": refresh_token, ...}), 201
```

- **Why it matters:** The entire phone-ownership trust model is bypassable. An attacker can mint unlimited accounts (rate limit is 5/hr per IP — trivially defeated) with random phone numbers, each holding a valid 30-day refresh token. Those accounts can create listings, open chats, and file reports. Every downstream control that assumes "a user is a verified phone" is void. It also poisons the user table with fake `070…` numbers that may collide with real users later. The sibling `/api/auth/register` route was already retired to `410` — this one was missed.
- **Additionally:** line **1793** returns the raw exception to the client: `return jsonify({"message": f"Signup failed: {str(e)}"}), 500`. The in-code comment says this is "during active testing" — it is live.
- **Recommended solution:** Delete the non-OTP branch (1698–1766) and return `410 Gone` like `/register`, so `/api/auth/signup` only completes an already-verified `phone/start` → `phone/verify` flow. Add OTP attempt-lockout to the OTP branch (line 1648 increments nothing). Replace the line-1793 message with a generic `"Signup failed"` and log server-side.
- **Change scope:** **Backend** (+ verify the Flutter signup screen only uses the OTP path).
- **How to test:** `curl -X POST $API/api/auth/signup -H 'Content-Type: application/json' -d '{"username":"attacker1","password":"Passw0rd!x"}'` — must return `4xx`, not `201` with tokens. Add a regression test in `kk/tests/test_signup_requires_otp.py` asserting no token is issued without a verified code.

---

### C-02 — REST chat image/video sends notify nobody

- **Severity:** CRITICAL · **Feature:** Messaging/chat
- **File:** `kk/routes/chat.py` · **Functions:** `send_message` (407–473), `send_image_message` (479–551), `send_video_message` (557–629)
- **Problem:** `emit_message_to_participants` is imported at line 16 but is called exactly **once** in the whole file — at line 209, inside `_emit_message_update` (used only for edits/deletes). The Socket.IO handler calls it at `kk/socketio_handlers.py:328`. The REST send endpoints never do.

Verified per endpoint:

| Endpoint | Persists | Socket emit | Push | `Notification` row |
|---|---|---|---|---|
| `POST /api/chat/<id>/send` (text) | ✅ `:450` | ❌ | ✅ `:461` | ❌ |
| `POST /api/chat/<id>/send_image` | ✅ `:545` | ❌ | ❌ | ❌ |
| `POST /api/chat/<id>/send_video` | ✅ | ❌ | ❌ | ❌ |
| `POST /api/chat/<id>/send_audio` | ✅ | ❌ | ✅ `:713` | ❌ |
| `POST /api/chat/<id>/send_media_group` | ✅ | ❌ | ✅ `:822` | ❌ |
| Socket `send_message` | ✅ | ✅ | ✅ | ✅ |

- **Why it matters:** The Flutter client deliberately falls back to REST when the socket is disconnected (`lib/features/chat/chat_live_transport.dart:1-19`, `chat_conversation_composer.dart:171-178`) — i.e. exactly on flaky mobile networks. In that state, a photo or video message is **saved to the database and then silently vanishes**: the recipient's open chat does not update, they get no push, and no in-app notification is created. The message only appears if they manually re-enter the conversation. For a marketplace where photos are the primary way buyers and sellers communicate about a car, this is a core-functionality failure.
- **Recommended solution:** After each successful commit in all five REST send handlers, call `emit_message_to_participants("new_message", msg.to_dict(), message=msg)`, `send_push(...)`, and create the `Notification` row — i.e. factor the socket handler's post-commit block (`socketio_handlers.py:328` onward) into one shared `deliver_message(msg)` helper and call it from both transports. That also fixes the REST/socket notification-feed inconsistency.
- **Change scope:** **Backend**.
- **How to test:** Client A connects via socket. Client B posts `POST /api/chat/<id>/send_image` over plain HTTP. Assert A receives a `new_message` socket event and a push, and that a `Notification` row exists. Add to `kk/tests/`.

---

### C-03 — Keyword search is unreachable from the app

- **Severity:** CRITICAL · **Feature:** Search
- **Files:** backend `kk/routes/cars.py:547`, `kk/listing_search.py:50-78`; frontend `lib/features/home/home_filters_query.dart`, `lib/features/home/home_search_filters_keyword.dart`
- **Problem:** The backend implements real search — Postgres `websearch_to_tsquery` against a `search_vector` column with an ILIKE fallback for SQLite:

```python
# kk/routes/cars.py:547
text_q = (request.args.get("q") or request.args.get("search") or "").strip()
```

The Flutter app **never sends it**. A repo-wide grep for a `q`/`search` query parameter in `lib/` returns exactly two hits, both unrelated:

```
lib/shared/dealer/dealer_socials.dart:202   queryParameters: {'q': name}      → social profile lookup
lib/shared/vin/open_vin_search.dart:7       Uri.https('www.google.com', ...)  → external Google search
```

`homeFiltersToApiQuery` (`home_filters_query.dart:177-266`) builds ~20 params — brand, model, trim, price, year, mileage, condition, transmission, fuel, body, drive, region, cylinders, seating, engine size, city, plate, title status, damaged parts, sort — but no `q`. The UI's search field filters the **locally bundled brand/model catalog** only (`home_search_filters_keyword.dart:40-52`).

- **Why it matters:** Users cannot search. Typing "Land Cruiser 2018 white" returns nothing useful; only the make/model picker works. There are also no recent searches (0 hits for `RecentSearch`), and the home search pill opens the filter sheet rather than a search field (`home_build.dart:87-94`), so the UI actively implies a capability that does not exist. This is table-stakes marketplace functionality and there is a fully built, indexed backend waiting for it.
- **Recommended solution:** Add `q` to `homeFiltersToApiQuery`, wire the keyword field to it with a 300–500 ms debounce, and render backend results alongside catalog suggestions. Also confirm the `a9b8c7d6e5f4_add_car_search_vector` migration's trigger is live on the production Postgres instance. Persist recent searches in `SharedPreferences`.
- **Change scope:** **Frontend** (primarily) + backend verification of the FTS trigger.
- **How to test:** Type a free-text query; assert the outbound request is `/api/cars?q=...`; assert results include listings whose description (not just make/model) matches. Add `test/home_search_query_test.dart` asserting `q` is present in the built query map.

---

### C-04 — Reviews and ratings do not exist

- **Severity:** CRITICAL (vs. spec) · **Feature:** Reviews
- **Files:** absent everywhere
- **Problem:** Verified by direct grep across both layers. Backend: no `Review` model in `kk/models.py`, no review blueprint, no `/reviews` route, no rating column. Frontend: no rating widget, no star UI, no review submission screen; `lib/pages/dealer_profile_page.dart:501` defines the dealer page sections as exactly `_DealerSection { about, listings }` — there is no reviews tab. The ~80 files matching "review" all refer to **moderation** ("Under review", "Review & Submit", dealer application review), which is a different concept.
- **Why it matters:** Reviews were requested as feature #14. In a used-car marketplace they are the primary trust signal for dealers; without them buyers have no way to assess a seller, and the platform has no reputation mechanism to deter bad actors. It is a full-stack feature (model + migration + endpoints + moderation + aggregate rating + dealer profile UI + write flow), not a UI addition.
- **Recommended solution:** Either build it (`Review` model with `reviewer_id`, `subject_user_id`, `car_id`, `rating 1-5`, `body`, `status`; unique on `(reviewer_id, subject_user_id)`; only after a completed chat/transaction to prevent spam; denormalized `rating_avg`/`rating_count` on `User`; moderation queue; dealer-profile tab), or explicitly descope from v1 and remove the expectation. **Do not ship a rating stub.**
- **Change scope:** **Multiple** — database + backend + frontend + admin.
- **How to test:** Full E2E — buyer chats seller, leaves a 4-star review, review enters moderation, admin approves, review appears on dealer profile, dealer aggregate rating updates, duplicate review rejected.

---

### C-05 — No payment integration exists

- **Severity:** CRITICAL (vs. spec) · **Feature:** Payments, Listing promotion
- **Files:** absent; documented in `docs/PAYMENTS.md`
- **Problem:** A repo-wide scan for `stripe|paypal|zaincash|fastpay|fib|payment|subscription|checkout|billing|in_app_purchase|revenuecat` finds **zero** matches in `kk/**/*.py` and no purchase flow in `lib/`. There is no `Payment`, `Subscription`, or `Order` model. `kk/app_settings.py` stores `featured_listing_price` and `dealer_subscription_price` as **display-only** strings that no checkout consumes. `docs/PAYMENTS.md` states this is intentional (deals settle off-platform). `kk/legal/terms.html:61-62` says paid promotions may exist "in the future or via offline billing". The help centre tells users the app does not process payments.
- **Why it matters:** Payments were requested as feature #19 and promotion as #20. Today "featured" is an admin-only boolean with **no expiry and no scheduled un-feature job**, so a promotion granted is permanent until an admin manually revokes it. There is no revenue path. Note the store-policy consequence: if you later add in-app purchase of featured placement, Apple and Google will require their IAP SDKs and take commission — a web-checkout workaround will be rejected. This decision must be made deliberately, not discovered at review time.
- **Recommended solution:** Decide at the Phase 1 gate. If monetizing in v1: add `in_app_purchase` (StoreKit + Play Billing), a server-side receipt-validation endpoint, a `Promotion` model with `featured_until`, a Celery beat job to expire it, and feed-ordering that respects expiry. If not: descope explicitly and keep featured admin-only.
- **Change scope:** **Multiple** — database + backend + frontend + store configuration.
- **How to test:** Sandbox IAP purchase → receipt validated server-side → `featured_until` set → listing ranks first → after expiry a beat job un-features it → listing drops in ranking. Plus receipt-replay rejection.

---

### C-06 — A release Android App Bundle cannot be built

- **Severity:** CRITICAL · **Feature:** Release configuration
- **Files:** `android/app/build.gradle.kts:167-186`; `android/signing.properties` **absent**; `.github/workflows/flutter_ci.yml:57-60`
- **Problem:** `signing.properties` and the upload keystore are gitignored and not present. Gradle correctly refuses to proceed:

```kotlin
// android/app/build.gradle.kts:167-186
if (isProdReleaseBuild && !allowDebugReleaseSigning) {
    if (!hasStoreSigning) {
        throw GradleException(
            "Prod release builds require signing.properties (repo root or android/). " +
                "Set ALLOW_DEBUG_RELEASE_SIGNING=true only for local smoke-test builds.")
    }
}
```

Compounding this, GitHub CI runs `flutter build appbundle --release --flavor prod` with no signing files and without `ALLOW_DEBUG_RELEASE_SIGNING` — that step must be failing.

- **Why it matters:** No shippable artifact can be produced from this checkout. It also blocks verification of the App Links SHA-256 fingerprint: the live server publishes `9E:7A:AC:CF:…:97:E8`, but without the keystore you cannot run `scripts/print_android_app_link_sha.py --verify-host` to confirm it matches. A mismatch silently breaks verified deep links in production. And R8/minification is enabled with only ~18 lines of ProGuard rules (`android/app/proguard-rules.pro`) and no keeps for Sentry, Airbridge, or `image_cropper` — the first correctly signed minified build is also the first real test of whether reflection-based plugins survive.
- **Recommended solution:** Create the upload keystore, populate `android/signing.properties` from `signing.properties.example`, and store it in Codemagic as `CM_KEYSTORE*`. Fix or remove the GitHub CI prod-AAB step. Then run `scripts/build_prod_android.py` → `scripts/verify_aab_signing.py` → `print_android_app_link_sha.py --verify-host`, and smoke-test the minified build. The Gradle guard itself is good — keep it.
- **Change scope:** **Config** (+ CI).
- **How to test:** `python scripts/build_prod_android.py && python scripts/verify_aab_signing.py`, then install the AAB-derived APK and exercise chat, maps, image crop, push, and deep links to validate R8.

---

### C-07 — `pending_signup` table has no migration

- **Severity:** CRITICAL · **Feature:** Database migrations
- **Files:** `kk/models.py:345-368`; `migrations/versions/c9d8e7f6a5b4_add_dealer_account_fields.py:66-93`
- **Problem:** `PendingSignup` declares `__tablename__ = "pending_signup"` (`kk/models.py:352`), but **no migration ever creates it**. The only references are conditional alters guarded by an existence check:

```python
# migrations/versions/c9d8e7f6a5b4_add_dealer_account_fields.py:66-68
if _has_table(conn, "pending_signup"):
    pending_cols = _cols(conn, "pending_signup")
    with op.batch_alter_table("pending_signup", schema=None) as batch_op:
```

The table exists only in dev, where `db.create_all()` (`kk/app_factory.py:348-354`) or `kk/legacy_schema.py` conjures it.

- **Why it matters:** This is the visible symptom of A-02 (three parallel schema paths): the model layer and the migration layer have diverged and nothing detects it. On a migrations-only Postgres deploy the table is absent, so any query touching `PendingSignup` raises `UndefinedTable` → HTTP 500. It currently appears unused, which is exactly why it is dangerous: the moment someone wires it up it works locally and 500s in production. The same class of drift affects `car.status`/`car.region_specs` standalone indexes, and `account_type`/`dealer_status`, which `models.py:97-98` declares `nullable=False` while the migration adds them `nullable=True`.
- **Recommended solution:** Either add a proper `create_table("pending_signup")` migration or delete the dead model. Then add a CI guard that fails on model↔migration drift (compare `sqlalchemy.inspect` of a freshly migrated database against `db.metadata`) and run it on both SQLite and Postgres. Gate `db.create_all()` and `legacy_schema` so they can never run in production.
- **Change scope:** **Database** + backend + CI.
- **How to test:** Fresh Postgres → `flask db upgrade` → assert `pending_signup` exists and that every model's columns are present. Extend `scripts/ci_migration_smoke.py`.

---

### C-08 — Docker image cannot upload to R2

- **Severity:** CRITICAL (if Docker is a deploy path) · **Feature:** File storage
- **Files:** `Dockerfile:18-23`; `.dockerignore:27`; `kk/r2_ops.py:29,64`
- **Problem:** `kk/r2_ops.py` deliberately runs S3 operations in a subprocess (to dodge an eventlet/SSL `RecursionError`) and resolves the helper relative to the package:

```python
# kk/r2_ops.py:29
path = os.path.join(here, "..", "tools", "r2_s3_op.py")
# kk/r2_ops.py:64
raise RuntimeError("r2_s3_op.py missing")
```

But the Dockerfile copies only `kk/requirements.txt`, `gunicorn.conf.py`, `migrations`, and `kk` — and `.dockerignore:27` excludes `tools/` outright. `tools/roboflow_http.py` (license-plate blur) is missing for the same reason.

- **Why it matters:** In the container image, **every image and video upload fails** with `RuntimeError: r2_s3_op.py missing`, and plate blurring silently fails open. Users cannot post listing photos — for a car marketplace that is total failure of the primary flow. Render currently deploys from the repo (so `tools/` is present), which means this is a latent trap that detonates the day anyone switches to the container path or a Render blueprint change.
- **Recommended solution:** Add `COPY tools/r2_s3_op.py tools/roboflow_http.py /app/tools/` to the Dockerfile (or un-ignore `tools/` and copy it wholesale), and add a container smoke test that performs a real upload.
- **Change scope:** **Config** (Dockerfile / `.dockerignore`).
- **How to test:** `docker build` then `docker run` with R2 env vars set; `POST /api/cars/<id>/images` and assert a `200` plus a fetchable public URL.

---

### C-09 — No working test safety net

- **Severity:** CRITICAL · **Feature:** Tests, CI
- **Files:** `test/legacy_*_widget_test.dart`; `.github/workflows/backend_ci.yml`; `.github/workflows/flutter_ci.yml:47-49`
- **Problem:** Measured, not assumed:
  - `flutter test` → **275 passed, 43 failed** (318 total, 86.5%). The failures cluster in the legacy widget suite: `pumpWidget(MyApp)` throws "Multiple exceptions (29)" — e.g. `legacy_login_widget_test.dart` is 0/3. The UI drifted (phone-OTP fields) and the tests were not updated.
  - `flutter analyze` → **60 issues, 0 errors** (26 `unused_element`, 12 `use_build_context_synchronously`, 7 `unused_import`).
  - `pytest kk/tests` → **53 passed** — but `backend_ci.yml` never runs it. CI only runs `pip-audit`, `compileall`, factory smoke, and migration smoke.
  - `.github/workflows/flutter_ci.yml:47-49` falls back to `verify_preflight --skip-host` on failure, so CI stays green when the production host is down.
  - `integration_test/app_smoke_test.dart:31-37` asserts only that `MyApp` exists.
  - `ios-codemagic.yaml:8-10` triggers only on branch `revert-exact-6b82de9` — dead.
  - No test anywhere covers: token refresh on 401, offline UX, RTL layout, Socket.IO chat, or a full sell-wizard submission.
- **Why it matters:** With 43 red tests the suite is ignored, so it protects nothing — and it would not have caught C-01, C-02, or C-03. Note that C-03 (search never wired) is precisely the kind of frontend/backend contract gap an integration test catches and a mock-API test cannot, because the fake server answers whatever the client asks.
- **Recommended solution:** Fix or explicitly quarantine the 43 failures so red means red. Add `pytest kk/tests` to `backend_ci.yml`. Remove the preflight `|| --skip-host` fallback. Add the four missing high-value tests (token refresh, sell E2E, chat send both transports, offline). Fix the `ios-codemagic.yaml` trigger. Delete the stale committed `analyze.txt` (220 issues / 1 error, referencing a removed `main_backup.dart`) — it is gitignored yet tracked and actively misleads.
- **Change scope:** **Test** + config.
- **How to test:** `bash scripts/flutter_test_ci.sh` exits 0; `python -m pytest kk/tests -q` runs in CI; a PR that breaks the search query map fails CI.

---

### C-10 — Chat attachments are publicly accessible

- **Severity:** CRITICAL · **Feature:** Messaging, File storage, Security
- **File:** `kk/routes/chat.py:67-97` · **Function:** `_upload_chat_attachment`
- **Problem:** Attachments are stored under an unguessable key and served from a public bucket or a public static path, with no authorization check on read:

```python
# kk/routes/chat.py:67-97
ext = os.path.splitext(file_storage.filename or "")[1].lower()
if ext not in allowed_extensions:
    raise ValueError("Unsupported attachment format")
obj_key = f"{subdir}/{secrets.token_hex(16)}{ext}"
```

The resulting `{R2_PUBLIC_URL}/{subdir}/{token}{ext}` (or local `/static/chat_uploads/...`) is fetchable by anyone. Security rests entirely on URL secrecy. Validation is **extension-only** here — no magic-byte sniffing, unlike the listing-media path which does it properly via `kk/security.py:241-337`. Per-file size falls back to `MAX_CONTENT_LENGTH`, defaulting to **250 MB** (`kk/config.py:225-227`).

- **Why it matters:** Private one-to-one conversations routinely carry ID photos, documents, and personal images. Any URL that leaks — via a shared screenshot, a proxy log, browser history, an analytics pixel, or a support ticket — grants permanent unauthenticated access with no revocation. That is a data-protection exposure, and it also diverges from the listing-media path, which is correctly hardened. Separately, a 250 MB per-file ceiling on chat uploads is a cheap memory-exhaustion vector.
- **Recommended solution:** Move chat media to a private bucket and serve it through a short-lived presigned GET issued only to verified conversation participants (reuse the participant check in `kk/chat_realtime.py`). Add magic-byte validation via the existing `kk/security.py` helper and a per-file chat size cap (e.g. 10 MB images / 50 MB video).
- **Change scope:** **Backend** + infrastructure (+ frontend if URL handling changes).
- **How to test:** Upload an attachment in a chat between A and B; fetch the URL logged-out and as unrelated user C — both must return `403`. Upload an executable renamed `.jpg` — must be rejected.

---

### C-11 — Money stored as floating point

- **Severity:** CRITICAL (data integrity) · **Feature:** Car listings, Database
- **Files:** `kk/models.py:570` (`Car.price`), `kk/models.py:60` (`user_favorites.price_at_favorite`), initial migration `5f5f50c0c03d`
- **Problem:** Prices use SQL `Float` (IEEE 754 double), not `Numeric(12,2)` or integer minor units.
- **Why it matters:** Binary floats cannot represent common decimal values exactly, so prices drift on round-trips and arithmetic. In this app that is amplified by the hardcoded IQD conversion (`lib/features/sell/sell_currency_convert.dart:15-18`, rate `1420`): a USD price converted to IQD, stored as a float, and formatted for display can render as e.g. `14,199,999.99` instead of `14,200,000`. Price-range filters and price-drop alert comparisons (`kk/tasks/alert_tasks.py`) inherit the same imprecision, causing off-by-one-cent boundary misses. Migrating this after launch means a data migration over live listings — it is far cheaper now.
- **Recommended solution:** Migrate to `Numeric(12, 2)` (or integer minor units, which is safest for multi-currency) with an explicit backfill migration; update serializers and Dart parsing accordingly. Move the FX rate to backend configuration (see M-08).
- **Change scope:** **Database** + backend + frontend.
- **How to test:** Store `14200000.00`, `0.01`, and `999999.99`; read back and assert exact equality. Assert a `price_max=14200000` filter includes a listing priced exactly at that value.

---

## 4. MISSING FUNCTIONALITY

| ID | Sev | Feature | Detail |
|---|---|---|---|
| C-04 | CRITICAL | Reviews / ratings | Absent from all layers |
| C-05 | CRITICAL | Payments | Absent; promotion is admin-only and free |
| C-03 | CRITICAL | Keyword search | Backend exists, frontend never calls it |
| MI-01 | HIGH | Blocked-users management UI | `ApiService.getBlockedUsers()` exists (`lib/services/api/api_admin.dart:79`) but **no screen calls it** — users can block but never unblock |
| MI-02 | HIGH | Featured-listing expiry | No `featured_until` column, no un-feature job. Promotions are permanent |
| MI-03 | HIGH | Localized backend messages | No `language`/`locale` column on `User`; all API errors, push bodies, emails, and SMS are English-only |
| MI-04 | MEDIUM | Recent searches | 0 hits for `RecentSearch` in `lib/` |
| MI-05 | MEDIUM | Multi-device push | Single `user.firebase_token` column — last login wins, other devices go silent |
| MI-06 | MEDIUM | Moderation feedback loop | Rejection reasons stored in `admin_notes` but never delivered to the user |
| MI-07 | MEDIUM | Listing-photo cropping | `image_cropper` used only for avatars/covers (`lib/shared/media/pick_circular_image.dart:18`), not listing photos |
| MI-08 | MEDIUM | Upload cancellation | Sell submit shows a blocking `AbsorbPointer` overlay with no cancel (`sell_step5_build.dart:63-65`) |
| MI-09 | MEDIUM | Orphaned-file cleanup | Deleting an image removes the DB row but never the R2 object — unbounded storage growth |
| MI-10 | LOW | Certificate pinning | Plain `http.Client()`; no pinning |
| MI-11 | LOW | Tablet store screenshots | `store_assets/README.md:35` (optional) |
| MI-12 | LOW | Android backup rules | No `backup_rules.xml` / `data_extraction_rules.xml` |

---

## 5. BROKEN FUNCTIONALITY

| ID | Sev | Feature | File · Function | Problem |
|---|---|---|---|---|
| C-02 | CRITICAL | Chat | `kk/routes/chat.py:479-629` | REST image/video sends: no socket emit, no push |
| C-06 | CRITICAL | Release | `android/app/build.gradle.kts:167` | Prod AAB build hard-fails |
| C-07 | CRITICAL | Migrations | `kk/models.py:352` | `pending_signup` never created |
| C-08 | CRITICAL | Uploads (Docker) | `.dockerignore:27` | R2 helper missing from image |
| B-01 | HIGH | Analytics screen | `lib/app/production_routes.dart:157` | `AnalyticsPage` is routed but **zero** `pushNamed('/analytics')` calls exist — dead screen |
| B-02 | HIGH | Car detail offline | `lib/pages/car_details_page_load.dart:67-70` | On network failure with no cache, sets `car=null` → shows "car not found". Users are told a listing was deleted when they are merely offline |
| B-03 | HIGH | Saved-search auto-save | `lib/features/home/home_fetch_core.dart:770-771` | `Future<void> _autoSaveSearch() async {}` — empty body, disabled after a duplicate bug |
| B-04 | MEDIUM | Notification list errors | `lib/features/chat/chat_notifications_page.dart:96-102` | Sets `loading=false` with no error UI → permanently blank screen |
| B-05 | MEDIUM | Dead filter field | `lib/features/home/home_page.dart:79` | `contactPhone` is held in state and reset, but never sent to the API |
| B-06 | MEDIUM | Unread count | `kk/routes/chat.py:970-974` | Counts messages from blocked users and soft-deleted messages |
| B-07 | MEDIUM | Dealer-application notification | `chat_notifications_page.dart:147-149` | Tapping is a no-op |
| B-08 | MEDIUM | Connectivity detection | `lib/services/connectivity_service.dart:23-25` | `catch (_) { isOnline.value = true; }` — plugin failure is reported as "online"; Wi-Fi without internet also reads as online |
| B-09 | LOW | Sort fallback | `lib/features/home/home_fetch.dart:304-333` | Falls back to client-side reorder of the current page — user sees a wrong global order |

---

## 6. DATABASE ISSUES

**Chain integrity: verified good.** The full 42-revision chain was executed against in-memory SQLite and applied cleanly: root `5f5f50c0c03d` → single head `a3b4c5d6e7f8`, one intentional merge (`m1n2o3p4q5r6`), no duplicate revision IDs, no orphans, no broken `down_revision` links, no multiple heads.

| ID | Sev | Issue | File · Lines | Fix scope |
|---|---|---|---|---|
| C-07 | CRITICAL | `pending_signup` has no migration | `kk/models.py:352` | DB |
| C-11 | CRITICAL | Price as `Float` | `kk/models.py:570`, `:60` | DB + backend + frontend |
| D-01 | HIGH | **No `ON DELETE` on 29 of 30 FKs.** Only `AdminAccount.principal_user_id` sets `RESTRICT` (`kk/models.py:314`). Deleting a user relies on manual child deletion in `kk/routes/auth.py:920-952`; any admin SQL or future path leaves orphans in `message`, `listing_analytics`, `dealer_application` | `kk/models.py` | DB |
| D-02 | HIGH | **3 migrations swallow failures** — `c5f3a2d1e8b7`, `d4e5f6a7b8c9`, `w1x2y3z4a5b6` wrap operations in `try/except`, so a partially migrated database reports success | `migrations/versions/` | DB |
| D-03 | HIGH | **No connection pool config.** No `SQLALCHEMY_ENGINE_OPTIONS` → SQLAlchemy defaults with no `pool_pre_ping` or `pool_recycle`. Under gunicorn on Render this causes stale-connection errors and pool exhaustion | `kk/config.py:200-213` | Backend |
| D-04 | HIGH | ✅ **RESOLVED.** *(Was: non-atomic counters — `ListingAnalytics.increment_*` and the OTP/verification `attempts = int(...) + 1` sites did Python-side read-modify-write, losing increments under concurrency.)* Dead `Car.increment_views()` / `ListingAnalytics.increment_*()` methods deleted (zero callers, confirmed by repo-wide search). All 9 live OTP/verification attempt-counter sites (`kk/routes/auth.py`, `kk/routes/user.py`) now go through a single SQL `UPDATE ... SET col = COALESCE(col, 0) + 1` helper, `atomic_increment_attempts()` (`kk/security.py`), restricted to a fixed allow-list of the 3 attempt-counter columns. `ListingAnalytics` get-or-create (`kk/listing_metrics.py::get_or_create_analytics` / `_bulk_create_missing_analytics`) now uses dialect-appropriate `INSERT ... ON CONFLICT (car_id) DO NOTHING` instead of check-then-insert, closing the same race documented under D-07 for the analytics half. `bump_listing_metric()`'s `SET metric = metric + 1` was already atomic and is unchanged. See **D-04 Remediation Detail** below. | `kk/security.py`, `kk/routes/auth.py`, `kk/routes/user.py`, `kk/listing_metrics.py`, `kk/routes/analytics.py`, `kk/models.py` | Backend |
| D-05 | MEDIUM | ✅ **RESOLVED.** *(Was: nullability drift — `user.account_type`/`user.dealer_status`/`saved_search.filters` are `nullable=False` in the model, `nullable=True` in the migrations that created them.)* New migration `3f945e50c327` (D-05: enforce NOT NULL on user.account_type/dealer_status and saved_search.filters) performs an idempotent defensive backfill (`account_type→'user'`, `dealer_status→'none'`, `filters→'{}'`, each `WHERE ... IS NULL`) then applies `NOT NULL` on both dialects (`batch_alter_table` on SQLite, `ALTER COLUMN ... SET NOT NULL` on PostgreSQL). Investigation found no live write path (`kk/routes/auth.py`, `kk/admin_identity.py`, `kk/routes/saved_searches.py`) can currently produce a NULL in any of the three columns, so the backfill is a safety net, not a data-repair step. No model or route changes — the model declarations were already correct. The three columns were removed from `KNOWN_NULLABLE_DRIFT` in `kk/schema_drift.py`. See **D-05 Remediation Detail** below. | `migrations/versions/3f945e50c327_d05_nullability_hardening.py`, `kk/schema_drift.py` | DB |
| D-06 | MEDIUM | Missing FK indexes: `notification.user_id`, `user_action.user_id`, `password_reset.user_id`, `email_verification.user_id`, `token_blacklist.expires_at`, `user_report.status` | `kk/models.py` | DB |
| D-07 | MEDIUM | ⚠️ **Partially resolved by D-04.** `_get_or_create_analytics` (`kk/routes/analytics.py`) race is fixed — see D-04. `record_user_listing_view`'s check-then-insert (`kk/view_history.py:38-67`) is a separate, still-open TOCTOU race; it was explicitly scoped **out** of D-04 (different table/model, not a counter) and needs its own fix (likely the same `INSERT ... ON CONFLICT DO NOTHING` pattern) | `kk/view_history.py:38-67` | Backend |
| D-08 | MEDIUM | `profile_picture` is `String(200)` while other media URLs were widened to 2048 — long CDN URLs truncate | `kk/models.py:81` | DB |
| D-09 | MEDIUM | ✅ **CLOSED / NO ACTION REQUIRED.** *(Was: dealer backfill migration `j7k8l9m0n1p2` (lines 180-183 for `dealer_application`, lines 196-198 for `dealer_profile`) inserts placeholder data (`"Dealership"`, `"Not provided"`) in place of any NULL/empty `dealership_name`/`dealership_phone`/`dealership_location` on legacy dealer-flagged `user` rows, when migrating them into the new `dealer_application`/`dealer_profile` tables.)* Repository investigation confirmed this fallback logic is confined to that one historical, already-applied migration — no current live code path can generate these placeholders today: `_save_dealer_application()` (`kk/routes/user.py`), `_review_dealer_application()` (`kk/routes/admin.py`), and `_apply_dealer_profile()` (`kk/routes/auth.py`) all require non-empty `dealership_name`/`dealership_phone`/`dealership_location` before creating or approving a dealer application, and a repo-wide search found the literal strings `"Dealership"`/`"Not provided"` nowhere else in the codebase. Production verification performed 2026-09-08 via two read-only diagnostic queries against the real production PostgreSQL database (no data modified): `SELECT ... FROM dealer_application WHERE dealership_name = 'Dealership' OR dealership_phone = 'Not provided' OR dealership_location = 'Not provided'`, and the equivalent query against `dealer_profile`. Both returned **0 affected rows**. Therefore no placeholder data exists in production, and no cleanup, backfill, migration, or code change is required. | `j7k8l9m0n1p2:180-183`, `j7k8l9m0n1p2:196-198` | DB |
| D-10 | LOW | ✅ **CLOSED.** *(Was: duplicate reports allowed — no unique on `(reporter_id, car_id)`.)* Implemented in commit `a748d7656334f3dd2cab399b12bb73587c786f43` (migration revision `7ae553c40b45`): `ListingReport` now has `UniqueConstraint("reporter_id", "car_id", name="uq_listing_report_reporter_car")`; the migration verified and removed the one known historical production duplicate (`id=2`, `reporter_id=26`/`car_id=162`) before creating the constraint, and is fail-closed — it rolls back transactionally and raises loudly instead of deleting anything if any other unexpected duplicate group is found. `report_car()` (`kk/routes/cars.py`) now uses a dialect-appropriate `INSERT ... ON CONFLICT (reporter_id, car_id) DO NOTHING ... RETURNING id` upsert (201 on first report, 200 on repeat, never a 500). Production verification (2026-09-08) confirmed the known duplicate pair `(reporter_id=26, car_id=162)` now contains only `listing_report.id=1` (`id=2` was removed by the migration), and a duplicate-group query against production returned zero remaining duplicate `(reporter_id, car_id)` groups. Backend CI's real-PostgreSQL migration smoke (`scripts/ci_migration_smoke.py::_d10_listing_report_dedup_smoke`) passed on this exact commit, covering unique constraint creation, PostgreSQL duplicate-insert rejection, `report_car()` 201/200 behavior, unexpected-duplicate fail-closed behavior, transactional rollback, and successful re-upgrade. Local verification: 328 backend tests passed (`pytest kk/tests -q`) and all 21 D-10 focused tests passed (`kk/tests/test_d10_listing_report_duplicates.py`). | `kk/models.py:1119-1173`, `migrations/versions/7ae553c40b45_d_10_dedupe_historical_duplicate_and_.py`, `kk/routes/cars.py` | DB |
| D-11 | LOW | ✅ **CLOSED / NO ACTION REQUIRED.** *(Was: relational data in JSON columns — `dealership_phones`, `contact_phones`, `SavedSearch.filters` — no FK integrity.)* Repository investigation (2026-09-08) found none of the three fields actually stores a database entity reference: `User`/`DealerApplication`/`DealerProfile.dealership_phones` and `Car.contact_phones` are JSON lists of plain phone-number **strings** (e.g. `["+9647...", ...]`), and `SavedSearch.filters` is a flat dict of plain search-criteria **scalars** (e.g. `{"brand": "toyota", "min_price": 10000}`) — structurally consistent with `Car.brand`/`Car.model` themselves also being non-FK'd strings, not catalog-table IDs. No occurrence anywhere in the codebase treats any element of these three fields as a `car_id`/`brand_id`/`model_id`/user-id or any other foreign-key-shaped value. The audit's "no FK integrity" premise therefore does not apply to what is actually stored: there is no relational reference here to lose integrity on. No schema, migration, model, API, or test change is required. Note: production row *contents* were not directly inspected from this environment (no production DB access available here) — this closeout rests on exhaustive source-code archaeology of every read/write/serialization path, not on a production data query. Two genuinely separate, pre-existing gaps surfaced during this investigation remain open and untouched under their own audit items: **BE-07** (`SavedSearch.filters` has no size/depth/key validation) and **A-04** (SQL-side listing filters vs the Python saved-search alert matcher already drift on key names, e.g. `engine_type`/`fuel_type`) — neither was modified or bundled into this closeout. | `kk/models.py:111,408,473,631,1185` | Backend |
| D-12 | LOW | ✅ **CLOSED / NO ACTION REQUIRED.** *(Was: soft-delete inconsistency — `kk/view_history.py:31` checks only `is_active`, ignoring `status`.)* Repository investigation (2026-09-08) found the cited line is only one guard clause inside `record_user_listing_view()`: three lines later, the same function also calls `listing_visible_to_viewer()` (`kk/listing_visibility.py`), which enforces `Car.status` (public: `active`/`sold`; owner/admin-only: `pending`/`hidden`/`draft`). The read path, `GET /api/user/recently-viewed` (`kk/routes/user.py`), independently re-filters every listing against its *current* row state via `listings_visible_to_viewer_filter()`, which enforces both `Car.is_active` and `Car.status` together. This split is the same codebase-wide, intentional pattern used by every other caller of `listing_visible_to_viewer()` (`kk/routes/cars.py`, `kk/routes/favorites.py`, `kk/listing_metrics.py`, `kk/tasks/alert_tasks.py`): `is_active` (hard-delete-equivalent) is checked explicitly by the caller, while `status` (moderation state) is checked centrally through the shared visibility helper — the two were introduced together, by design, in commit `578ba0c` ("centralize listing visibility rules"). The audit's `:31` line citation is also stale: the later D-07 concurrency fix added a long docstring above this logic in `kk/view_history.py`, shifting it to roughly line 79 without changing its behavior. Separately, `User.status` does not exist anywhere in this codebase — `User` has no `status` column, only the unrelated `dealer_status` (dealer-application state); account state is represented solely by `User.is_active`, enforced upstream of `view_history.py` at the JWT chokepoint (`check_if_token_revoked`, `kk/routes/auth.py`) and in `get_current_user()` (`kk/auth.py`) — this finding concerns `Car.is_active`/`Car.status` only, not `User`. No exposure path was found and no code, migration, or config change is required. One hardening opportunity was noted but is **not** part of this closeout and is **not** treated as an outstanding D-12 defect: `kk/tests/test_d07_view_history_upsert.py` has no test covering a non-`active`/non-`sold` `Car.status` on either the write path or the (currently untested) `GET /api/user/recently-viewed` read path. | `kk/view_history.py`, `kk/listing_visibility.py`, `kk/routes/user.py` | Backend |

#### D-04 Remediation Detail (implemented)

**Scope:** OTP/verification attempt counters + `ListingAnalytics` get-or-create. No DB migration required (no schema change — same columns/tables, only the SQL used to read/write them changed). No thresholds, lockout durations, reset behavior, API status codes/messages, ownership filtering, response ordering, or response shape were changed.

- **`kk/security.py`** — new `atomic_increment_attempts(user, field_name)`: a single SQLAlchemy Core `UPDATE user SET <field> = COALESCE(<field>, 0) + 1 WHERE id = :id`, followed by `db.session.refresh(user, attribute_names=[field_name])` to read back the true post-increment value inside the same transaction (no commit inside the helper — callers keep their existing commit). `field_name` is validated against a fixed allow-list (`phone_verification_attempts`, `dealer_email_verification_attempts`, `email_change_attempts`) so it can never become a generic "update any column" primitive.
- **`kk/routes/auth.py`** (4 sites) and **`kk/routes/user.py`** (5 sites) — every `attempts = int(getattr(user, field, 0) or 0) + 1; user.field = attempts` read-modify-write replaced with `attempts = atomic_increment_attempts(user, field)`. All surrounding threshold checks, lockout-duration math, resets, commits, exceptions, status codes, and messages are byte-for-byte unchanged.
- **`kk/listing_metrics.py`** — new `get_or_create_analytics(car)` and `_bulk_create_missing_analytics(missing_car_ids)`, both using a dialect-appropriate `INSERT ... ON CONFLICT (car_id) DO NOTHING` (`sqlalchemy.dialects.postgresql.insert` / `sqlalchemy.dialects.sqlite.insert`, selected via `bind.dialect.name`, matching the idiom already used elsewhere in this codebase). `bump_listing_metric()` now calls `get_or_create_analytics()` instead of inline check-then-insert; its atomic `SET metric = metric + 1` is unchanged.
- **`kk/routes/analytics.py`** — the duplicated local `_get_or_create_analytics()` was deleted. The single-listing endpoint uses the shared `get_or_create_analytics()` helper (commits only when a row was actually created, same as before). `get_listings_analytics()` keeps its original two-SELECT / single-conditional-commit shape and O(1) round trips: the missing-id list is built in Python from the already-fetched `existing` set, then created in **one** multi-row `_bulk_create_missing_analytics()` call — no per-row commits, no extra SELECTs.
- **`kk/models.py`** — deleted dead, never-called `Car.increment_views()` and `ListingAnalytics.increment_views/messages/calls/shares/favorites()` (each had the same read-modify-write race; confirmed zero callers repo-wide before deletion).

**Tests:**
- `kk/tests/test_d04_atomic_counters.py` (new, 15 tests, SQLite): normal/NULL/sequential atomic increments, unsupported-field rejection, OTP lockout threshold/reset regression via the real `_consume_phone_otp()`, analytics row creation/idempotency/existing-row behavior, unrelated-DB-error (FK violation) propagation, `bump_listing_metric()` regression.
- `kk/tests/test_signup_otp_required.py` (existing, 27 tests) re-run unchanged as an OTP regression gate — all pass.
- `scripts/ci_migration_smoke.py` (extended, Postgres-only, runs in the existing migration-smoke CI job — no new CI job added): `_d04_atomic_increment_primitive_smoke` (20 concurrent threads incrementing one counter → exactly 20, no lost updates), `_d04_otp_lockout_concurrency_smoke` (4 concurrent wrong attempts → 4 `otp_invalid`/no lockout; 5 concurrent wrong attempts → exactly 1 `otp_locked` + 4 `otp_invalid`, using the real `_consume_phone_otp()` with independent app contexts/sessions per thread and barrier synchronization), `_d04_analytics_concurrency_smoke` (20 concurrent `bump_listing_metric()` calls on a fresh car → exactly one `ListingAnalytics` row, `views == 20`).

**Remaining D-04-adjacent concern:** `record_user_listing_view` (`kk/view_history.py`) has a structurally similar check-then-insert race but is tracked separately under D-07 (different model/purpose — recently-viewed history, not a counter) and was explicitly out of scope here.

#### D-05 Remediation Detail (implemented)

**Scope:** schema-nullability-only. Three columns — `user.account_type`, `user.dealer_status`, `saved_search.filters` — had been declared `nullable=False` in `kk/models.py` since they were added, but the migrations that created them (`c9d8e7f6a5b4_add_dealer_account_fields.py`, `w1x2y3z4a5b6_add_alerts_retention_tables.py`) left the real database column `nullable=True`, with no follow-up `SET NOT NULL`. No model changes (the model declarations were already correct), no route changes (investigation found every live write path already supplies a non-NULL value), and no FK/`ondelete` behavior touched (that is D-01's domain, already resolved).

- **`migrations/versions/3f945e50c327_d05_nullability_hardening.py`** (new, head revision, `down_revision = d7e6c32b1689`) — `upgrade()`: idempotent defensive backfill (`UPDATE ... SET <col> = <default> WHERE <col> IS NULL`, matching zero rows in the expected/common case) followed by `NOT NULL` enforcement, per column, on both dialects — `op.batch_alter_table(...).alter_column(..., nullable=False)` on SQLite (SQLite has no native `ALTER COLUMN`), `ALTER TABLE ... ALTER COLUMN ... SET NOT NULL` on PostgreSQL. `downgrade()` reverses only the constraint (`nullable=True`); existing data is never touched on the way down, since relaxing `NOT NULL` can never violate existing rows.
  - **SQLite FK-pragma interaction (found and fixed during implementation):** the D-01 cascade FKs (`saved_search.user_id ON DELETE CASCADE`, etc.) are enforced on SQLite only via the `PRAGMA foreign_keys=ON` connection-level listener in `kk/app_factory.py`. Alembic's SQLite batch mode adds `NOT NULL` by recreating the *entire* `user` table (rename → create → copy → drop old); with FK enforcement on, dropping the renamed old `user` table would cascade-delete every D-01 cascade-linked child row for every user. The migration disables FK enforcement for its own `user`/`saved_search` batch-alters and restores it immediately after. Because SQLite treats `PRAGMA foreign_keys` as a no-op while a transaction is open, and Alembic runs the whole upgrade/downgrade as one logical transaction, the toggle is done via a defensive `COMMIT` (ignoring the harmless "no transaction is active" case) immediately before each `PRAGMA` statement — otherwise the restore-to-ON silently failed to apply, permanently disabling FK enforcement for the rest of the process (this was caught by a full-suite regression in `test_d04_atomic_counters.py`/`test_saved_search_delete.py` during implementation, before it was fixed). PostgreSQL never takes this branch — it has native transactional DDL and its FKs are enforced unconditionally by the engine, not a per-connection pragma.
- **`kk/schema_drift.py`** — removed `("user", "account_type")`, `("user", "dealer_status")`, `("saved_search", "filters")` from `KNOWN_NULLABLE_DRIFT`; the drift checker (`test_migration_schema_drift.py`) now fails if any of the three ever regress to nullable again.

**Tests:**
- `kk/tests/test_d05_nullability_backfill.py` (new, SQLite): downgrades to the revision immediately before D-05, seeds a "dirty" (raw-SQL, explicit `NULL`, bypassing ORM defaults) and a "clean" row per table, re-upgrades, then asserts the dirty rows were backfilled to the documented defaults, the clean rows were left untouched, and a raw `sqlite3` insert with an explicit `NULL` is now rejected by the database itself (not merely by the ORM).
- `kk/tests/test_migration_schema_drift.py` (existing) re-run unchanged — passes now that the three entries are removed from `KNOWN_NULLABLE_DRIFT`.
- `scripts/ci_migration_smoke.py::_d05_nullability_hardening_smoke` (new, PostgreSQL-only, wired into the existing migration-smoke CI job): same downgrade/reseed/re-upgrade shape as `_c11_price_numeric_round_trip`, against real PostgreSQL — verifies backfill, preservation of existing non-NULL data, `information_schema`-level `NOT NULL`, and that PostgreSQL itself rejects a raw `NULL` insert/update on each of the three columns. Self-cleaning (deletes its own seeded rows in a `finally` block). **Not yet run locally** — no local PostgreSQL/Docker instance was available in this environment; verification depends on the GitHub Actions migration-smoke job.
- Full backend suite (`pytest kk/tests`, 287 tests) and `python -m compileall kk migrations scripts` both pass with no regressions (baseline before D-05: 286 passed).

---

## 7. SECURITY ISSUES

| ID | Sev | Issue | File · Lines | Fix scope |
|---|---|---|---|---|
| C-01 | CRITICAL | Signup bypasses phone verification | `kk/routes/auth.py:1698-1766` | Backend |
| C-10 | CRITICAL | Chat attachments world-readable | `kk/routes/chat.py:67-97` | Backend + infra |
| H-01 | HIGH | **Tokens survive password change/reset.** `change_password` (`:713-744`) and `reset_password` (`:1089-1143`) set the new hash but never blacklist existing JTIs. A stolen token stays valid up to 60 min (access) / 30 days (refresh) — so the standard "change your password" incident response does not evict the attacker | `kk/routes/auth.py` | Backend |
| H-02 | HIGH | **Banned users keep working tokens.** Deactivation sets `is_active=False` but does not revoke JTIs. Refresh is blocked (`:590-591`), but the existing access token works on any route that skips `get_current_user()` | `kk/routes/admin.py:1616-1646` | Backend |
| H-03 | HIGH | **Presigned R2 uploads bypass content validation.** `r2_sign_upload` trusts the client's declared `content_type`; the client PUTs directly to R2 with no server-side magic-byte check | `kk/routes/media.py:398-487` | Backend + infra |
| H-04 | HIGH | **Unapproved dealer profiles are public.** `dealer_profile` checks only `account_type == "dealer"`, not `dealer_status == "approved"` — unlike `list_dealers`, which does | `kk/routes/user.py:1057-1062` | Backend |
| H-05 | HIGH | **Exact dealer GPS coordinates in public payloads.** `dealership_latitude`/`longitude` appear in the public `User.to_dict()`, embedded in the `seller` object of every listing in the browse feed | `kk/models.py:257-258` | Backend |
| H-06 | HIGH | **Fail-open rate limiter.** `rate_limit_check` returns `True` (allow) on database error; `reset_password`'s per-user limit is skipped entirely if Redis fails | `kk/auth.py:283-301`, `kk/routes/auth.py:1130-1131` | Backend |
| H-07 | HIGH | **Token fallback to unencrypted storage.** `TokenStore` mirrors access and refresh tokens into plain `SharedPreferences` when Keychain/EncryptedSharedPreferences write fails | `lib/shared/auth/token_store.dart:106-135` | Frontend |
| M-01 | MEDIUM | `dev_code` (the OTP) is returned in API responses when `DEBUG` **or** `APP_ENV=development`. Gating on `DEBUG` alone is fragile — one misconfigured deploy leaks every OTP in JSON | `kk/routes/auth.py:826-832,1361,1487`; `kk/routes/user.py:1177,1590` | Backend |
| M-02 | MEDIUM | Account-existence enumeration: `forgot_password` returns `503` when the user exists and SMS fails, `200` when the user does not exist | `kk/routes/auth.py:1062-1072` | Backend |
| M-03 | MEDIUM | OTP codes logged in full by the console SMS provider | `kk/sms_service.py:219,374` | Backend |
| M-04 | MEDIUM | Internal exception text returned to clients (signup 500, `get_cars` 500) | `kk/routes/auth.py:1793`; `kk/routes/cars.py:657-659,780-782` | Backend |
| M-05 | MEDIUM | `BCRYPT_LOG_ROUNDS = 12` is configured but `bcrypt.init_app(app)` is never called — actual work factor unverified | `kk/config.py:246`; `kk/app_factory.py` | Backend |
| M-06 | MEDIUM | No image count cap on `POST /api/cars/<id>/images`; no `Image.MAX_IMAGE_PIXELS` → decompression-bomb DoS | `kk/routes/media.py:531-560`; `kk/media_processing.py:250-264` | Backend |
| M-07 | MEDIUM | `MAX_CONTENT_LENGTH` defaults to **250 MB** | `kk/config.py:225-227` | Config |
| M-08 | MEDIUM | Plate blur fails open — uploads succeed with unblurred plates if Roboflow errors or `ROBOFLOW_API_KEY` is unset | `kk/media_processing.py:197-199` | Backend |
| M-09 | MEDIUM | No per-account login lockout — IP rate limit only, so distributed password spraying against one account is unthrottled | `kk/routes/auth.py` | Backend |
| M-10 | MEDIUM | Reported listings stay publicly visible with no auto-hide threshold | `kk/routes/cars.py:1506-1514` | Backend |
| M-11 | MEDIUM | Firebase client keys committed (`google-services.json`, `GoogleService-Info.plist`). Normal for mobile, **but** they must be restricted by package/bundle + SHA-1 in the Google Cloud console — unverified | `android/app/src/prod/`, `ios/Runner/` | Config |
| M-12 | MEDIUM | `?mode=developer` in **production** iOS associated domains | `ios/Runner/Runner.entitlements:12-17` | Config |
| L-01 | LOW | Report resolutions are not audit-logged | `kk/routes/admin.py:1172-1226` | Backend |
| L-02 | LOW | admin-web CSP allows `'unsafe-inline' 'unsafe-eval'` | `admin-web/src/middleware.ts:23` | Frontend |
| L-03 | LOW | EXIF not explicitly stripped (`save(exif=b'')`) — re-encoding drops most metadata incidentally | `kk/media_processing.py` | Backend |
| L-04 | LOW | Unused `mobile_scanner` + `geocoding` deps keep camera permission justified by a non-existent VIN scanner — store-review risk | `pubspec.yaml:42,63` | Frontend |

---

## 8. BACKEND / API ISSUES

| ID | Sev | Issue | File · Lines |
|---|---|---|---|
| BE-01 | HIGH | ✅ **CLOSED.** *(Was: unbounded dealer listings — `dealer_profile` does `.all()` on every public dealer page load; `kk/routes/user.py:1066-1071`.)* Investigation confirmed the finding was valid: `GET /api/dealers/<dealer_public_id>` (`dealer_profile()`, `kk/routes/user.py`) ran an unbounded `.all()` query for a dealer's active public listings, with no application-level cap on how many active listings a dealer account can accumulate, and `stats.total_listings` was derived from `len(...)` of that same unbounded list rather than a real count. Implemented in commit `bb020d6d6c039422bf86d29c92688b7ba7717dfe`: the returned `listings` array is now hard-capped at 200 (`_DEALER_PROFILE_LISTINGS_CAP`) via `.limit(200)` on the existing `public_listings_filter(...)`-filtered, `selectinload`-eager-loaded query, while `stats.total_listings` is computed from a separate `COUNT(*)` query built from the exact same `public_listings_filter(...)` base query (no `.limit()`/`selectinload()`/ordering), so the stat stays the true total even once the array is capped. The existing `is_featured DESC, created_at DESC` ordering and the overall `{dealer, listings, stats}` response shape are unchanged; `stats.featured_listings` was intentionally left as-is (still derived from the capped/returned listings, not from a separate count) since the approved fix scope covered only `total_listings`. Real cursor/offset pagination was deliberately NOT introduced here, because the current Flutter dealer-profile screen (`lib/pages/dealer_profile_page.dart`) has no load-more/pagination support and expects the complete listings array in a single response — adding page/per_page semantics without a matching client change would have silently hidden listings for any dealer above the cap. A dealer exceeding 200 active public listings today would only ever see the 200 most-recent/featured ones on their own public page; full pagination (with a corresponding Flutter change) remains a future cross-stack enhancement if that becomes a realistic scenario. Verified via the repository test suite (no production/staging runtime check performed, and no production listing-count data was measured or assumed): dedicated BE-01 tests (`kk/tests/test_be01_dealer_profile_listings_cap.py`) — 10 passed, covering over-cap capping with an accurate total, under-cap/no-listings unchanged behavior, featured-first/created-at-descending ordering preserved across the cap boundary, and inactive/pending/hidden/draft listings excluded from both the returned array and the `COUNT(*)`; relevant existing dealer-profile/regression tests (`kk/tests/test_h05_dealer_map_location.py`, `test_signup_otp_required.py`, `test_d08_profile_picture_width.py`, `test_user_public_dict_privacy.py`) — 54 passed, unmodified; full backend suite (`pytest kk/tests`) — 418 passed, 0 failed; `python -m py_compile`, `python -m compileall -q kk`, and `git diff --check` all passed. | `kk/routes/user.py` |
| BE-02 | HIGH | ✅ **CLOSED.** *(Was: N+1 queries — favorites [`kk/routes/favorites.py:28-41`], recently-viewed [`kk/routes/user.py:569-579`], and analytics [`kk/routes/analytics.py:46-63`] call `to_dict()` without eager loading, lazily fetching images/videos/seller per row; `/api/cars` does this correctly [`kk/routes/cars.py:554-559`].)* Investigation confirmed the finding was valid with measured, current-code evidence (real Flask app + real SQLite, `before_cursor_execute` query counting, no ORM/query mocking): favorites and recently-viewed scaled from 16 SQL queries at N=5 favorited/viewed cars to 46 at N=20 (~2 extra queries per additional row); analytics scaled from 11 to 26 (~1 extra query per additional row). Implemented in commit `662e53b1d9d127498626495f8299963684607c0f`: added targeted SQLAlchemy eager-loading to the exact same three endpoints, mirroring the existing `/api/cars` pattern — `get_favorites()` (`kk/routes/favorites.py`) and `recently_viewed()` (`kk/routes/user.py`) now use `.options(selectinload(Car.images), selectinload(Car.videos), joinedload(Car.seller))` on their driving query, and `get_listings_analytics()` (`kk/routes/analytics.py`) uses `.options(joinedload(ListingAnalytics.car).selectinload(Car.images))` on the `ListingAnalytics` query whose rows are actually returned (intentionally *not* eager-loading `videos`/`seller` there, since `ListingAnalytics.to_dict()` never reads them). Re-measured post-fix with the same methodology: all three endpoints now issue a constant 7 queries at both N=5 and N=20 — no linear growth. No pagination, filtering, ordering, serialization, response shape, authorization, or visibility logic was changed in any of the three endpoints. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-02 tests (`kk/tests/test_be02_n_plus_one.py`) — 6 passed, covering correctness (200 response with expected images/videos/seller/analytics fields) and query-count-is-constant-not-linear regression for all three endpoints, using a distinct seller per car per dataset so a missing `seller` eager-load couldn't hide behind SQLAlchemy's identity-map cache for a single shared seller; a sanity check reverting the favorites fix confirmed its dedicated query-count test fails without the eager-load, proving the test genuinely detects the regression; relevant existing tests (`test_d07_view_history_upsert.py`, `test_d04_atomic_counters.py`, `test_d01_fk_ondelete.py`, `test_h05_dealer_map_location.py`, `test_user_public_dict_privacy.py`, `test_token_revocation.py`) — 76 passed, unmodified; full backend suite (`pytest kk/tests`) — 424 passed, 0 failed; `python -m compileall -q kk` and `git diff --check` both passed. Explicitly out of scope and not touched: the separate, pre-existing unbounded-`.all()` result-set-size issue on `/api/analytics/listings` (a distinct concern from N+1 eager-loading) was left untouched under BE-02. | `kk/routes/favorites.py`, `kk/routes/user.py`, `kk/routes/analytics.py` |
| BE-03 | HIGH | ✅ **CLOSED.** *(Was: scheduled notifications can double-send — `for row in due: row.status = "sending"; commit()` with no `SELECT ... FOR UPDATE`, so two beat workers (or any two concurrent callers) could process the same row; `kk/notification_broadcast.py:206-224`.)* Implemented in commit `4c3ee3659142a525e5ffdc739272b2f9dc870e93` ("fix: atomically claim scheduled notifications"): `process_due_scheduled_notifications()` (`kk/notification_broadcast.py`) now claims each due row with a single atomic, conditional SQL `UPDATE scheduled_notification SET status='sending', updated_at=... WHERE id = :id AND status = 'pending'`, executed via `db.session.execute(update(...))`. Only the caller whose `UPDATE` affects exactly one row (`rowcount == 1`) proceeds to call `execute_broadcast()` for that row; `rowcount == 0` means another worker already claimed it between the initial `SELECT` and this `UPDATE`, and the row is skipped without broadcasting. No other behavior was changed: `execute_broadcast()`, `resolve_recipients()`, the admin notification routes (`kk/routes/admin.py`), Celery configuration/tasks, the `ScheduledNotification` model/migrations, API response shapes, and authorization/permissions are all unmodified; existing `sent`/`failed`/`cancelled` handling is unchanged. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-03 tests (`kk/tests/test_be03_scheduled_notification_atomic_claim.py`) — 7 passed, covering normal claim-and-send, a row already `sending` not being reclaimed, `sent`/`cancelled`/`failed` rows never reclaimed, two sequential simulated claim attempts on the same row (only the first wins), and a real race against the production function itself (a competing claim interleaved via a SQLAlchemy `after_cursor_execute` hook) resolving to exactly one broadcast; a sanity check reverting the fix confirmed this last test fails against the pre-fix implementation (observed `created: 1`, i.e. a real double-broadcast), proving it genuinely detects the original race; full backend suite (`pytest kk/tests`) — 431 passed, 0 failed; `python -m compileall -q kk`, `python -m compileall -q scripts`, and `git diff --check` all passed. Additionally validated with a real-thread, real-PostgreSQL concurrency smoke (`scripts/ci_migration_smoke.py::_be03_scheduled_notification_claim_smoke`, following the same convention as D-04's `_d04_otp_lockout_concurrency_smoke`/`_d04_analytics_concurrency_smoke`): GitHub Actions "Backend CI" → "Migration smoke (Postgres)" job (a real ephemeral Postgres 16 service container) ran on this exact commit (`4c3ee3659142a525e5ffdc739272b2f9dc870e93`) and completed successfully, reporting "BE-03: atomic claim OK under concurrency (8 due rows, 4 racing workers, each row claimed exactly once)" followed by "migration smoke OK" — 8 due `pending` scheduled notifications were seeded, 4 concurrent real threads (each with its own Flask/SQLAlchemy session) raced to call `process_due_scheduled_notifications()`, every notification was claimed/sent exactly once in aggregate (never 0, never 2+), competing workers' already-claimed rows were skipped without broadcasting, all 8 rows ended in status `sent`, exactly 8 `Notification` rows existed, and all seeded rows were cleaned up. This CI migration-smoke run is the PostgreSQL evidence for this fix; it is a CI validation, not a production/staging runtime test, and no production/staging runtime check was performed. | `kk/notification_broadcast.py` |
| BE-04 | HIGH | **Synchronous broadcast fan-out.** `execute_broadcast` sends FCM to up to 5000 users inside the HTTP request | `kk/notification_broadcast.py:106-128` |
| BE-05 | HIGH | **Invalid FCM tokens never cleared.** Permanent failures (`NotRegistered`) are logged but `user.firebase_token` is not nulled, so dead tokens are retried forever | `kk/push.py:252-270` |
| BE-06 | MEDIUM | ✅ **CLOSED.** *(Was: unbounded `.all()` on `/api/my_listings`; `kk/routes/cars.py:1460-1464`.)* Implemented in commit `4a0a8c2788a71a94100a537c898eddd13a941d72` ("fix: cap and optimize legacy my listings endpoint"): `compat_my_listings()` (`kk/routes/cars.py`) now hard-caps the returned array at 200 rows (`_MY_LISTINGS_COMPAT_CAP = 200`, via `.limit(_MY_LISTINGS_COMPAT_CAP)`) and eager-loads the query with `selectinload(Car.images)`, `selectinload(Car.videos)`, and `joinedload(Car.seller)`, while the existing bare-JSON-array response contract and filtering behavior are unchanged. `/api/user/my-listings` was intentionally left untouched, since it is already paginated. No Flutter changes were required. Verified via the repository test suite (no production/staging runtime check performed beyond the deployment check below): dedicated BE-06 tests (`kk/tests/test_be06_my_listings_cap.py`) — 10 passed; a sanity check reverting the fix confirmed the dedicated tests fail without the implementation; relevant regression tests — 23 passed; full backend suite (`pytest kk/tests`) — 489 passed, 0 failed; `python -m compileall -q kk` and `git diff --check` both passed. Deployed to production: Render deployed this exact commit (`4a0a8c2`) successfully and reported Live; `GET /health` returned HTTP 200 after deployment. | `kk/routes/cars.py` |
| BE-07 | MEDIUM | ✅ **CLOSED.** *(Was: saved-search `filters` JSON has no size/depth/key limits; `kk/routes/saved_searches.py:18-21`.)* Implemented in commit `5febd259d9575c50ce865e770e25ce7062a2333b` ("fix: bound saved search filter payloads"): `_clean_filters()` (`kk/routes/saved_searches.py`) is now the single choke point all three saved-search write paths pass through — `POST /api/saved-searches`, `PUT /api/saved-searches/<id>`, and `POST /api/saved-searches/sync` — and enforces a maximum of 30 filter keys (`_MAX_FILTER_KEYS`), a maximum 64-character key length (`_MAX_FILTER_KEY_LEN`), and a maximum 500-character string value length (`_MAX_FILTER_VALUE_LEN`): oversized keys are dropped, oversized string values are truncated (not dropped), oversized non-string scalar values are dropped, and nested dict/list values are dropped (no depth beyond flat scalars is permitted). The pre-existing None/empty-string filtering behavior is preserved unchanged. Compatibility was reviewed against `kk/listing_filters.py` and the Flutter saved-search persistence path; legitimate filter values are scalar and remain compatible. Verified via the repository test suite (no production/staging runtime check performed beyond the deployment check below): dedicated BE-07 tests (`kk/tests/test_be07_saved_search_filter_bounds.py`) — 18 passed; a sanity check reverting only the implementation confirmed 15/17 BE-07 tests fail without it, and restoring it returned all tests to passing, proving the tests genuinely detect the regression; full backend suite (`pytest kk/tests`) — 506 passed, 0 failed; `python -m compileall -q kk` and `git diff --check` both passed. Deployed to production: Render deployed this exact commit (`5febd25`) successfully and reported Live; Gunicorn started successfully using `gthread`; the PostgreSQL migration startup step succeeded; `GET /health` returned HTTP 200 repeatedly; Firebase initialized successfully; no BE-07-related startup/runtime errors were observed. | `kk/routes/saved_searches.py` |
| BE-08 | MEDIUM | ✅ **CLOSED.** *(Was: `_find_by_filters` loads all of a user's saved searches on every create/sync; `kk/routes/saved_searches.py:29-34`.)* Investigation found the original claim **PARTIALLY VALID**: the single-item `POST /api/saved-searches` create path's `_find_by_filters()` call is already bounded by the pre-existing `_MAX_SAVED_SEARCHES=50` cap and is cheap by itself, and was left unchanged. The real remaining defect was in `sync_saved_searches()` (`kk/routes/saved_searches.py`): it already loaded the user's existing `SavedSearch` rows once into an in-memory `existing` dict, but for every sync item without a matching `public_id` it called `_find_by_filters()`, re-fetching the same user's rows from the database again, and for genuinely new items it also ran a separate `COUNT(*)` instead of using the already-known in-memory count — up to ~156 SQL statements measured for a 50-item worst-case sync request in SQLite. Implemented in commit `f3644aecb9c660db45b12d1c30b4ad088d0b3a4f` ("fix: eliminate redundant saved search sync queries"): `sync_saved_searches()` now builds an in-memory filter-fingerprint lookup (`fingerprint_lookup`) from the already-loaded `existing` rows, using the exact same `_filters_fingerprint()` semantics `_find_by_filters()` already used, and matches non-public_id-matched sync items against it entirely in memory instead of re-querying the database; the lookup is kept up to date as the loop progresses (a matched row's stale fingerprint is dropped and replaced by its new one only when it actually changes) so that same-request deduplication and "first matching row wins" semantics are preserved unchanged — e.g. two new sync items with identical filters in one request still collapse to a single row. The per-new-item `COUNT(*)` was replaced with a running `current_count` seeded from `len(existing)` and incremented only when a genuinely new row is accepted, with the existing `_MAX_SAVED_SEARCHES=50` cap enforced exactly as before. No database schema change, migration, fingerprint column/index, cache, or background task was introduced; ownership, notify/auto_saved/name handling, public_id handling (including stale-public_id fallback to fingerprint matching), timestamps, response shape (`{"saved_searches": [...]}`), and commit behavior are all unchanged. Verified via the repository test suite (no production/staging runtime check performed beyond the deployment/verification check below): dedicated BE-08 tests (`kk/tests/test_be08_saved_search_sync_queries.py`) — 10 passed, covering query-amplification (exactly one unbounded `SELECT ... FROM saved_search` regardless of batch size, not one per item), zero `COUNT(*)` queries, existing-filter dedup, same-request dedup of new items with identical filters, stale-public_id fallback to fingerprint matching, true-new-item creation, the 50-row cap, response-envelope compatibility, the existing-public_id fast path, and query-count scaling across a small vs. large batch; a sanity check temporarily reverting only the implementation (test file kept) confirmed 4 of the 10 dedicated tests fail against the old code (query amplification, no-redundant-count, same-request dedup, and scaling), proving the tests genuinely detect the original defect, and restoring the implementation returned all 10 to passing; relevant existing tests (`kk/tests/test_saved_search_delete.py`, `kk/tests/test_be07_saved_search_filter_bounds.py`) — 18 passed, unmodified; full backend suite (`pytest kk/tests`) — 516 passed, 0 failed; `python -m compileall -q kk` and `git diff --check` both passed. Deployed to production: Render deployed this exact commit (`f3644ae`) successfully and reported Live; `GET /health` returned HTTP 200 repeatedly; `/api/cars`, `/api/config/trust`, `/terms`, `/privacy`, `/.well-known/assetlinks.json`, `/.well-known/apple-app-site-association`, and `/health/push` all returned HTTP 200; no BE-08-related deployment/runtime errors were observed in the supplied Render logs. | `kk/routes/saved_searches.py` |
| BE-09 | MEDIUM | ✅ **CLOSED.** *(Was: **Inconsistent response shapes** — `/api/cars` → `{cars, pagination}`; `/cars`, `/api/my_listings`, `/api/analytics/listings` → bare arrays; `/api/cars/<id>` → `{car}`. Plus camelCase `plateType`/`plateCity` duplicating snake_case fields; `multiple`.)* Investigation found the original claim **PARTIALLY VALID / MITIGATED-BY-DESIGN**: the differing response envelopes are real and confirmed by a live in-process probe (real Flask app + real SQLite, no mocking) — `GET /api/cars` and `GET /api/user/my-listings` return `{"cars": [...], "pagination": {...}}`, `GET /cars`, `GET /api/my_listings`, and `GET /api/analytics/listings` return bare JSON arrays, and `GET /api/cars/<id>` returns `{"car": {...}}` — every one returning HTTP 200 with valid, correctly-shaped JSON and no client-side parsing failure. However, these shapes are **intentional compatibility/legacy contracts** (the routes' own docstrings call them "Compatibility alias" / "Legacy alias for mobile clients"), and the current Flutter client (`lib/`) already has dedicated parsers/accessors for each shape — `_makeAuthenticatedRequest` (Map-typed) for the enveloped endpoints, `makeAuthenticatedListRequest`/`getAuthenticatedJsonList` (List-typed) explicitly for `/api/my_listings` and `/api/analytics/listings`, and shape-tolerant helpers (`listingMapsFromApiResponse`, `unwrapCarApiPayload`, `parseCarDetailPayload`) that accept either a bare list or `{cars: [...]}` / `{car: ...}`. No envelope standardization was performed: unifying these shapes now would create unnecessary compatibility risk for legacy/unknown clients that may still depend on the bare-array contracts, with no demonstrated production benefit or defect to justify it. The camelCase `plateType`/`plateCity` response duplicates (`kk/models.py` `Car.to_dict()`) were confirmed genuinely redundant — every client read site already checks `plate_type`/`plate_city` first (or exclusively) — but were intentionally left untouched: measured impact is only ~46 bytes/car, and removal is optional cosmetic cleanup, not a correctness/security/performance fix. Therefore **no application code, test, or migration changes were made** for BE-09. Verified via investigation only (static code/call-path tracing plus the live in-process probe described above); no production/staging runtime check was performed and no production data was assumed. Explicitly out of scope and not touched under BE-09: the separate, pre-existing unbounded `.all()` on `GET /api/analytics/listings` (`kk/routes/analytics.py`) discovered during this investigation — this is a distinct concern from response-shape consistency and is left for a future, separate finding. | multiple |
| BE-10 | MEDIUM | ✅ **CLOSED.** *(Was: ~106 broad `except Exception` handlers in route files, many without `db.session.rollback()`; `kk/routes/chat.py` returns generic 500s **without logging**.)* Investigation found the original "~106" figure was **not an accurate count** and does not reflect the actual scoped remediation below; the historical audit wording is left unedited per BE-10 closeout scope, but closure is based on the real, verified fix rather than that figure. Implemented in commit `78b22bf6f6c579d231acf0efc341733a244eba77` ("fix: improve route exception observability"): 24 route-boundary `except Exception` handlers across `kk/routes/chat.py`, `kk/routes/auth.py`, `kk/routes/analytics.py`, `kk/routes/favorites.py`, `kk/routes/cars.py`, and `kk/routes/user.py` were addressed — 14 `kk/routes/chat.py` handlers (`list_chats`, `get_messages`, `send_message`, `send_image_message`, `send_video_message`, `send_audio_message`, `send_media_group_message`, `edit_chat_message`, `delete_chat_message`, `unread_count`, `block_user`, `unblock_user`, `report_user`, `list_blocked_users`) now log the caught exception via a new `_log_route_exception()` helper (or, for the 6 of them that already write to the DB, via `current_app.logger.exception(...)` alongside their pre-existing `db.session.rollback()`); and 10 previously-unprotected DB-writing handlers received both `db.session.rollback()` and exception logging for the first time — `logout`, `change_password`, `verify_email`, `verify_phone`, `phone_verify` (`kk/routes/auth.py`), `get_listings_analytics`, `get_listing_analytics` (`kk/routes/analytics.py`), `toggle_favorite` (`kk/routes/favorites.py`), `upload_profile_picture` (`kk/routes/user.py`), and `delete_car` (`kk/routes/cars.py`, routed through the existing `_listing_db_error_response()` helper already used by `create_car`/`update_car`). No response status code, response body/message, or success-path behavior was changed anywhere; existing handlers that already had both rollback and logging were left untouched, as were intentional best-effort exception guards elsewhere in the codebase. Broad `except Exception` handler *types* were deliberately **not** narrowed globally — this fix addresses missing rollback/logging at route boundaries only, not exception-type specificity. Verified via the repository test suite (no production/staging runtime check performed beyond the deployment check below): dedicated BE-10 tests (`kk/tests/test_be10_route_exception_logging.py`) — 23 passed; a negative-test sanity check confirmed all 23 dedicated tests fail against the pre-fix implementation and pass again once the fix is restored, proving the tests genuinely detect the original gap; relevant regression tests — 282 passed; full backend suite (`pytest kk/tests`) — 539 passed, 0 failed; `python -m compileall kk` and `git diff --check` both clean. Deployed to production: Render deployed this exact commit (`78b22bf`) successfully and reported Live; Gunicorn started successfully using `gthread`; Firebase initialized successfully; `GET /health` returned HTTP 200 repeatedly; no startup/runtime errors attributable to this change were observed. A separate, unrelated possible issue involving `migrations/env.py`'s `logging.config.fileConfig(..., disable_existing_loggers=True)` was discovered during this work and is explicitly **out of scope** — not fixed, and not part of this closure. | `kk/routes/` |
| BE-11 | MEDIUM | ✅ **CLOSED.** *(Was: Two divergent view metrics: `Car.views_count` (detail GET) vs `ListingAnalytics.views` (track endpoint).)* Investigation confirmed the finding was valid: both counters shared the same underlying per-(user, listing) dedup flag (`user_viewed_listings`, via `record_user_listing_view()`), so a real, authenticated, non-seller view only ever incremented one of the two counters, never both, depending on undefined request-arrival order between the detail-page GET and `POST /api/analytics/track/view`. Implemented in commit `0978720f16d02ad09c41d6135f0889299848b2c9` ("fix: decouple analytics view deduplication"): a new, dedicated `ListingViewClaim` table (`kk/models.py`) with a database-enforced `UNIQUE(user_id, car_id)` constraint now gates `ListingAnalytics.views` independently of the detail-page GET's `Car.views_count` bump. A new atomic helper, `claim_listing_view_once()` (`kk/listing_metrics.py`), performs a single dialect-aware `INSERT ... ON CONFLICT DO NOTHING ... RETURNING` against this table — the database's own unique constraint, not any Python-side check, is the concurrency guarantee. `record_trusted_view()` now calls `claim_listing_view_once()` to decide whether to increment `ListingAnalytics.views`, instead of reusing the `is_first_view` result of `record_user_listing_view()`; `record_user_listing_view()` itself, its recently-viewed tracking behavior, `Car.views_count`, `claim_unique_engagement()` (used only by calls/shares), and `record_call_or_share()` are all unmodified. Redis is not used for this permanent view-dedup claim in any way — the database is the sole source of truth. Verified via the repository test suite (no production/staging runtime check performed beyond the deployment check below): dedicated BE-11 tests (`kk/tests/test_be11_analytics_view_dedup.py`) — 17 passed, covering first/repeat track-view counting, seller-self-view exclusion, both GET-then-track and track-then-GET orderings, interleaved combinations, Redis-absent operation, concurrent claims (including a real multi-thread SQLite race test), migration upgrade/downgrade/re-upgrade with the unique constraint enforced, unchanged calls/shares behavior, and explicit proof that `user_viewed_listings` and `listing_view_claim` are independent tables; a negative-test sanity check (temporarily reverting only the implementation) confirmed the exact GET-then-track regression test fails against the old coupled logic and passes again once restored, proving the tests genuinely detect the original defect; full backend suite (`pytest kk/tests`) — 556 passed, 0 failed; a real-thread, real-PostgreSQL concurrency smoke (`scripts/ci_migration_smoke.py::_be11_listing_view_claim_smoke`, 20 racing threads) confirmed exactly one winning claim and exactly one database row; schema-drift check clean; `python -m compileall` and `git diff --check` both passed. Deployed to production: Render deployed this exact commit (`0978720`) successfully and reported Live; Gunicorn started successfully using `gthread`; Firebase initialized successfully; `GET /health` returned HTTP 200 repeatedly; no startup or migration errors were present in the supplied deployment logs. | `kk/models.py`, `kk/listing_metrics.py` |
| BE-12 | MEDIUM | ✅ **CLOSED.** *(Was: Celery fails **open** — if Redis is down, `retention_dispatch.py` runs alert tasks inline in the web process; `celery_app.py` falls back to `memory://`; `kk/retention_dispatch.py:12-21`.)* Investigation confirmed the finding was **partially valid**: `dispatch_saved_search_alerts`/`dispatch_price_drop_alerts` (`kk/retention_dispatch.py`) did catch any exception from `Task.delay()` and, on failure, ran the alert task function directly and synchronously inside the calling Flask/Gunicorn request — but `memory://` itself does **not** execute tasks inline (it silently queues them with no consumer); the real trigger was a broker/backend connection failure. Measured with a real, unmocked Celery/kombu call against a genuinely unreachable Redis: `.delay()` did not fail fast — `Celery.send_task()` subscribes for the eventual result (`backend.on_task_call()`) *before* publishing, which hit the Redis result backend's own connection retry policy (default `max_retries=20`, ~1s apart) and blocked the calling request thread for **~64 seconds** before raising, only then falling into the in-request synchronous execution. Implemented in commit `06329de27ad32c94c1ef2586d3f2e64c973a2220` ("fix: prevent synchronous Celery alert fallback"): both dispatch functions now enqueue via `apply_async(..., ignore_result=True, retry=False)` instead of `.delay()` — `ignore_result=True` skips the backend result-consumer subscription that caused the ~64s block, and `retry=False` disables Celery's own broker-publish retry loop, so a broker failure raises immediately instead of retrying inline. On any enqueue failure the failure is now only logged (`kk.retention_dispatch`, narrowed to `celery.exceptions.OperationalError` with a defensive broad `except Exception` as a last-resort safety net) and the function returns; **the synchronous inline task-execution fallback was removed entirely and cannot be silently reintroduced** (guarded by a dedicated regression test). Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-12 tests (`kk/tests/test_be12_retention_dispatch.py`) — 12 passed, covering successful enqueue via `apply_async` with the expected `ignore_result`/`retry` options for both alert types, enqueue failure never running the task body inline, enqueue failures being logged, dispatch failures never propagating to the `create_car`/`update_car` callers, prompt return on enqueue failure (no multi-second block), a static regression guard against the old `.delay()`/direct-call fallback pattern reappearing, and a real (non-mocked) subprocess-based integration check against a genuinely unreachable broker confirming no retry storm and a fast return; relevant existing tests (`kk/tests/test_celery_flask_context.py`, `kk/tests/test_be03_scheduled_notification_atomic_claim.py`, and the price-drop-alert coverage in `scripts/smoke_tests/test_backend_factory_smoke.py`) — all passed, unmodified; full backend suite (`pytest kk/tests`) — 443 passed, 0 failed; `python -m py_compile`, `python -m compileall -q kk`, and `git diff --check` all passed; Backend CI #1024, Flutter CI #1096, and Admin Web CI #212 all passed for this commit. **BE-13 is explicitly separate and remains OPEN/partially valid** — whether a Celery worker/beat process is actually provisioned and consuming the queue in production is unverified by this repository (`Procfile` defines `worker`/`beat`, but `start_render.sh` only starts gunicorn) and was intentionally not addressed by this fix; a reachable broker with no consuming worker still makes `apply_async()` return successfully today (the message is queued, not lost, and not executed inline), which is BE-13's concern, not BE-12's. This closure makes **no claim** about whether a Celery worker/beat process is actually running in production — it only closes the specific fail-open/request-blocking defect in `retention_dispatch.py` itself. | `kk/retention_dispatch.py` |
| BE-13 | MEDIUM | `Procfile` defines `worker`/`beat` but `start_render.sh` starts only gunicorn — scheduled notifications depend on manually provisioned Render services (**UNKNOWN**) | `Procfile`, `start_render.sh` |
| BE-14 | MEDIUM | `/api/analytics/track/message` and `/track/favorite` are **no-op** endpoints the client still calls | `kk/routes/analytics.py` |
| BE-15 | LOW | ✅ **CLOSED.** *(Was: LIKE metacharacters (`%`, `_`) unescaped in brand/model filters — pathological pattern performance; `kk/routes/cars.py:573-575`.)* Implemented in commit `fad9d900377bc7cd82471aa7357e4cf5d9e14549`: added a `_like_escape()` helper (`kk/routes/cars.py`) that escapes backslash, `%`, and `_` (backslash first) before a raw filter value is wrapped in the route's own `%...%` wildcards, with the SQLAlchemy `.ilike(..., escape="\\")` explicit escape character passed alongside the escaped value. Applied to every wildcard-wrapped raw-input filter in both car-listing routes: `brand`, `model`, `trim`, `location`, `color`, `plate_city` in `get_cars()`, and `brand`, `model`, `location` in the legacy `get_cars_alias()`. Exact-match filters (`drive_type`, `fuel_type`) were left unchanged since they were never wildcard-wrapped. The fix prevents a caller-supplied `%`/`_` from being interpreted as a SQL `LIKE` wildcard, while preserving normal case-insensitive substring-search behavior for metacharacter-free values. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-15 tests (`kk/tests/test_be15_like_escaping.py`) — 18 passed; relevant car-search regression tests (`kk/tests/test_car_search_relevance.py`) — 23 passed; full backend suite (`pytest kk/tests`) — 363 passed; `python -m py_compile` and `git diff --check` both passed. | `kk/routes/cars.py` |
| BE-16 | LOW | ✅ **CLOSED.** *(Was: Case-sensitive exact match on `condition`/`transmission` filters; `kk/routes/cars.py:594-602`.)* Implemented in commit `25e3db8b551a235c2649b34744d72ad252c8d9a4`: the `condition` and `transmission` filters in both `get_cars()` (`GET /api/cars`) and the legacy `get_cars_alias()` (`GET /cars`) now match case-insensitively, using the existing `func.lower(...)` pattern already applied to the adjacent `body_type` filter (`func.lower(Car.condition) == condition.strip().lower()`, and likewise for `transmission`). Normal same-case filter behavior (the common path) is unchanged. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-16 tests (`kk/tests/test_be16_case_insensitive_condition_transmission.py`) — 14 passed, with the same tests demonstrated to fail 10/14 against the pre-fix implementation; relevant regression tests (`kk/tests/test_be15_like_escaping.py`, `kk/tests/test_car_search_relevance.py`) — 41 passed; full backend suite (`pytest kk/tests`) — 377 passed, 0 failed; `python -m py_compile` and `git diff --check` both passed. | `kk/routes/cars.py` |
| BE-17 | LOW | ✅ **CLOSED.** *(Was: `list_blocked_users` N+1 (`db.session.get` per block); `kk/routes/chat.py:1168-1171`.)* Implemented in commit `1a8441e12502edd7cb1d2c3534a81797d925b038`: `list_blocked_users()` (`GET /api/users/blocked`) was changed from an N+1 per-user lookup (`db.session.get(User, ...)` once per `BlockedUser` row) to a single batched `User.query.filter(User.id.in_(...))` lookup, mirroring the existing `users_by_id` pattern already used by `list_chats()` in the same file. Response ordering (the underlying `BlockedUser` row order, not dict-iteration order) and the existing behavior of silently skipping a `blocked_id` whose `User` row no longer exists were both preserved; no schema or migration change was required. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-17 tests (`kk/tests/test_be17_blocked_users_batch_fetch.py`) — 5 passed, including a query-count regression test confirming a constant (not linear-in-block-count) number of SQL statements; relevant chat tests — 58 passed; full backend suite (`pytest kk/tests`) — 382 passed, 0 failed; `python -m py_compile` and `git diff --check` both passed. | `kk/routes/chat.py` |
| BE-18 | LOW | ✅ **CLOSED.** *(Was: no message-send idempotency — client retries create duplicates; `kk/routes/chat.py`.)* Implemented in commit `82f583b0841d657f4985e1963b86d483c6394d9b`: all five REST chat-send endpoints (`send_message`, `send_image_message`, `send_video_message`, `send_audio_message`, `send_media_group_message` in `kk/routes/chat.py`) now support `Idempotency-Key` / `X-Idempotency-Key` replay protection, reusing the existing `kk/idempotency.py` `replay_response()`/`remember_response()` helper already relied on by `create_car` (API-01) — a matching key on a retry returns the original response verbatim instead of re-uploading media or inserting a second `Message` row, and a missing/blank key preserves prior behavior unchanged. On the client, `OutgoingChatSendService` (`lib/services/outgoing_chat_send_service.dart`) generates exactly one idempotency key per logical send attempt and threads it through `ApiService`/`api_chat.dart` into the request headers, so the same key is preserved across automatic transport-level retries of that same attempt where applicable (the `_sendWithAdaptiveTimeout` timeout retry for text sends, and the 401 token-refresh retry for all five send types); a new user-initiated send always generates a fresh key. Net effect: duplicate sequential retries of the same logical send — timeout retries, 401-refresh retries, or any other retry of an identical request — no longer create a duplicate `Message` row or repeat delivery side effects (push notification, `Notification` row, Socket.IO `new_message` event). Explicitly out of scope: Socket.IO message sending (`kk/socketio_handlers.py`, the separate real-time send path) was not modified and has no idempotency protection — this fix covers the REST send endpoints only. Known limitation, not fixed here: two genuinely concurrent requests carrying the identical key can still both pass `replay_response()` before either calls `remember_response()` and create two `Message` rows — this check/remember race is a pre-existing limitation of the shared `kk/idempotency.py` helper (equally present in `create_car`/API-01 today), not introduced or fixed by this change; no current client retry path triggers it (all client-side retries are sequential/awaited, never concurrent), so it is tracked as a separate follow-up against `kk/idempotency.py` rather than fixed under BE-18. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-18 backend tests (`kk/tests/test_be18_chat_send_idempotency.py`) — 15 passed, covering same-key replay with a single `Message`/single delivery side effect, no-key and different-key backward compatibility, blank-key handling, cross-endpoint-scope non-collision, and the documented (pre-existing) no-request-body-fingerprinting limitation of the shared helper; dedicated BE-18 Flutter tests (`test/api_chat_test.dart`) — 8 passed, 0 failed, covering key propagation, key omission, and fresh-key-per-logical-send (the pre-existing unrelated Flutter suite failures tracked under C-09 are unaffected by this change); full backend suite (`pytest kk/tests`) — 397 passed, 0 failed; `git diff --check` passed. | `kk/routes/chat.py` |
| BE-19 | LOW | ✅ **CLOSED.** *(Was: no OpenAI spend cap beyond a 20/hr rate limit; `kk/ai_service.py:239-325`.)* Implemented in commit `789e83c33d702ddc2eda8da6a4d7690b47d60adb`: `POST /api/suggest-car-specs` now layers three independent controls on top of each other — (1) the existing per-user `@rate_limit(max_requests=20, window_minutes=60, per_ip=False)` decorator (`kk/routes/ai.py`, unmodified), (2) a new GLOBAL (cross-user) daily request budget via `check_global_daily_budget()` (`kk/security.py`), claimed BEFORE `suggest_car_specs_from_ymm()`'s OpenAI call and never refunded on a subsequent OpenAI failure, configurable via `AI_SPECS_MAX_CALLS_PER_DAY` (`kk/.env.example`; falls back to a documented default of 200/day if unset or invalid), and (3) a per-request `max_completion_tokens` output ceiling on the OpenAI Chat Completions payload (`kk/ai_service.py`) — chosen over the legacy `max_tokens`, which OpenAI's o-series/reasoning models and the GPT-5 family reject outright, since `OPENAI_MODEL` is an existing, operator-configurable, unvalidated env var. This is a global request-count-based cost-exposure cap, not literal USD/token-spend accounting — no billing table or dollar tracking was added. The global budget uses the same Redis `INCR` (+ `EXPIRE`-on-first-increment) atomic primitive already used by the existing per-user/IP rate limiter, so it is concurrency-safe on the Redis path (concurrent requests cannot jointly exceed the configured cap); its dev/test-only in-process fallback (used only when Redis is absent and the existing `ALLOW_INMEMORY_RATE_LIMITS`/development-or-testing escape hatch applies) is explicitly protected by its own `threading.Lock` around the full read-check-increment-write sequence, not the GIL. In production without Redis (or on a Redis error), the request fails closed with `503`, consistent with the project's existing H-06 rate-limit posture — unchanged, and not weakened. Known limitations, not fixed here: the daily window is a fixed 24-hour window that begins when its Redis key is first created (not a calendar-midnight reset), identical in nature to the existing per-user/IP limiter's own hourly windows; and the same tiny pre-existing risk already present in the existing rate limiter — a crash/connection-drop between the `INCR` and the following `EXPIRE` call could in principle leave a key without a TTL — is inherited unchanged by the new budget check (not introduced or fixed by this change). Explicitly out of scope and not touched: `/api/analyze-car-image` (still disabled/placeholder-gated outside dev, unaffected), and the Flutter client — `/api/suggest-car-specs` is not currently called anywhere in `lib/`, so no Flutter integration was added or changed. Verified via the repository test suite (no production/staging runtime check performed): dedicated BE-19 tests (`kk/tests/test_be19_ai_spend_cap.py`) — 11 passed, covering global-cap enforcement and OpenAI-call suppression once exhausted, budget sharing across different users, deterministic window-reset simulation, independence from the existing per-user limiter, Redis fail-closed/escape-hatch behavior, the `max_completion_tokens` payload (and absence of `max_tokens`), unchanged success-response shape, and dedicated concurrency tests for both the Redis-backed and in-process-fallback counters; relevant existing rate-limit/AI/security regression tests (`kk/tests/test_h06_rate_limit_fail_closed.py`, `test_be15_like_escaping.py`, `test_be16_case_insensitive_condition_transmission.py`, `test_be17_blocked_users_batch_fetch.py`, `test_be18_chat_send_idempotency.py`, `test_signup_otp_required.py`) — 89 passed; full backend suite (`pytest kk/tests`) — 408 passed, 0 failed; `python -m compileall -q kk` and `git diff --check` both passed. | `kk/security.py`, `kk/routes/ai.py`, `kk/ai_service.py` |
| BE-20 | LOW | ✅ **CLOSED.** *(Was: dead code — `validate_ownership` and `secure_headers` decorators defined but never applied; `kk/security.py:498-538,431-450`.)* Investigation confirmed the finding was valid: a repo-wide search (source, tests, Flutter) and a `git log -S"@validate_ownership"` / `-S"@secure_headers"` pickaxe across the full commit history found zero call sites, ever — neither decorator was applied to any route at any point in this project's history. Implemented in commit `d79cc2c990f1a3da26b7cb4a02d2038f2785fdfb`: both `secure_headers()` and `validate_ownership()` were deleted from `kk/security.py`. No runtime behavior changed, because there were zero call sites to begin with. Security headers continue to be applied globally by the existing `@app.after_request` hook (`kk/app_factory.py`), and resource ownership continues to be enforced by the existing inline `seller_id`/`is_admin` checks already present in the relevant routes (`kk/routes/cars.py`, `kk/routes/media.py`, `kk/routes/analytics.py`) — neither mechanism was touched. Verified via the repository test suite (no production/staging runtime check performed): full backend suite (`pytest kk/tests`) — 408 passed, 0 failed, before and after the change; `python -m py_compile` / `python -m compileall -q kk` and `git diff --check` all passed. | `kk/security.py` |

---

## 9. FLUTTER ISSUES

| ID | Sev | Issue | File · Lines |
|---|---|---|---|
| H-07 | HIGH | Token fallback to plaintext prefs | `lib/shared/auth/token_store.dart:106-135` |
| F-01 | HIGH | **`getCarDetail` swallows every error** — `catch (_) { return null; }` makes a network failure, a 401, and a 500 indistinguishable from a deleted listing. Root cause of B-02 | `lib/services/api/api_listings.dart:86-109` |
| F-02 | HIGH | **Missing `API_BASE` crashes release at first network call.** `effectiveApiBase()` throws `StateError` if the dart-define is absent. CI supplies it, so this bites on manual/local release builds | `lib/services/config.dart:106-110` |
| F-03 | HIGH | `NumberFormat.decimalPattern()` called with **no locale** — ignores the active language | `lib/pages/tiktok_scroll_listing_card.dart:61,82` |
| F-04 | MEDIUM | `setState` after `await` without a `mounted` guard | `lib/pages/production_favorites_page.dart:58,72,81-86,90-95` |
| F-05 | MEDIUM | **AuthGuard can spin forever** — shows a spinner while `auth.isLoading \|\| ApiService.isAuthenticated`; a token present in memory plus a failed profile load leaves the user stuck with no timeout or error path | `lib/pages/carzo_shared.dart:237-238` |
| F-06 | MEDIUM | No request cancellation — no `CancelToken`; navigating away mid-flight leaves work running | `lib/services/api/` |
| F-07 | MEDIUM | `getCarContactPhones` returns `[]` on any non-200, so contact buttons silently disappear | `lib/services/api/api_listings.dart:113-131` |
| F-08 | MEDIUM | Push-token registration failures only `print` in debug — a user can silently have no push at all | `lib/services/push_notification_service.dart:356-363` |
| F-09 | MEDIUM | 12 `use_build_context_synchronously` analyzer warnings | `lib/features/sell/sell_step5_build.dart:272+` |
| F-10 | MEDIUM | 26 `unused_element` + 7 `unused_import` warnings — dead code in the sell flow | `lib/features/sell/sell_flow.dart` etc. |
| F-11 | MEDIUM | No offline mutation queue — chat sends and listing uploads fail immediately with no retry affordance | |
| F-12 | LOW | `success`/`json.decode` on a 2xx body is not wrapped in try/catch | `lib/services/api/api_http.dart:182` |
| F-13 | LOW | Drafts silently vanish on corrupt prefs (`catch (_) {}` → empty list) | `lib/pages/my_listings_page.dart:235-240` |
| F-14 | LOW | Hardcoded `carr-5hrm.onrender.com` shipped in all three locale bundles as `apiBaseHint` | `lib/l10n/app_{en,ar,ku}.arb:396-397` |
| F-15 | LOW | Mixed navigation styles — ~33 `Navigator.push` call sites alongside the named-route table | |
| F-16 | LOW | `kBuildSha` defaults to `'dev'` unless a CI dart-define overrides it | `lib/pages/carzo_shared.dart:47-49` |

---

## 10. UI/UX AND LOCALIZATION ISSUES

**Localization is a genuine strength, with one structural gap.** All three locales have **803 keys with zero missing** — only 3 Arabic and 6 Kurdish values remain identical to English (`apiBaseHint`, `appTitle`, `whatsappHint`, plus `apiLabel`, `unit_liter_suffix`, `value_transmission_cvt` in Kurdish). RTL discipline is unusually good: **zero** `EdgeInsets.only(left:/right:)` across 436 files.

| ID | Sev | Issue | File · Lines |
|---|---|---|---|
| MI-03 | HIGH | **Backend strings are English-only and there is no way to fix it per user.** `User` has no `language`/`locale` column, so API errors (`kk/routes/auth.py:224`), push bodies (`kk/socketio_handlers.py:294`), saved-search alerts (`kk/tasks/alert_tasks.py:76`), emails (`kk/email_service.py:147`), and SMS (`kk/sms_service.py:185`) are all English. The client displays API `message` verbatim (`lib/shared/errors/user_error_text.dart:30-33`), so an Arabic user who mistypes a password sees "Invalid credentials" | multiple |
| U-01 | HIGH | Hardcoded English in critical UI: force-update gate (`lib/app/widgets/force_update_gate.dart:59,70,77,119,133` — "Update required", "Update now"), navigation errors (`lib/app/production_routes.dart:103-104,125-126`), release crash screen (`lib/app/bootstrap.dart:84-85`) | |
| U-02 | MEDIUM | **~15 non-directional icons break RTL** — `Icons.arrow_back` at `tiktok_scroll_listing_card.dart:185`, `sell_car_page.dart:89`, `my_listings_page.dart:529`, `recently_viewed_page.dart:370`, `sell_draft_gate.dart:673`, `car_details_page_build_hero.dart:417`; `Icons.chevron_right` at `production_settings_page.dart:170`, `sell_step{1,2,3}_pickers.dart` | |
| U-03 | MEDIUM | **Arabic/Kurdish relative times lack ICU plurals.** English uses `{count, plural, one{} other{}}` (`app_en.arb:348`); ar/ku use bare interpolation, so `daysAgo` renders "منذ 1 أيام" (plural noun with 1) | `lib/l10n/app_ar.arb:349`, `app_ku.arb` |
| U-04 | MEDIUM | **Bundled fonts have no Arabic/Kurdish glyphs.** Orbitron and BarlowCondensed are Latin-only and `AppFonts.orbitron` is used at 30+ sites with no `fontFamilyFallback`. Rendering falls back to whatever the OS provides, which varies by Android OEM | `pubspec.yaml:156-162` |
| U-05 | MEDIUM | Parallel inline i18n via `_tr()` helpers instead of ARB — report dialog (`lib/shared/trust/report_dialog.dart:28-124`), comparison strings, legal pages, `my_listings_page.dart:6-14` | |
| U-06 | MEDIUM | 90 `maxLines: 1` occurrences with no adjacent `overflow:` — truncation risk with longer Arabic/Kurdish text | |
| U-07 | MEDIUM | Kurdish uses Arabic Material/Cupertino delegates as a proxy (`lib/shared/i18n/ku_delegates.dart:16-53`), so date pickers and system strings render Arabic. `ckb` is referenced in helpers but absent from `supportedLocales` | |
| U-08 | MEDIUM | Search pill opens the filter sheet rather than a search field — implies a capability that does not exist (see C-03) | `lib/features/home/home_build.dart:87-94` |
| U-09 | LOW | Arabic-Indic digits deliberately disabled to avoid past mojibake — consistent, but worth an explicit product decision | `lib/shared/i18n/digits.dart:6-9` |
| U-10 | LOW | Language names hardcoded (`Text('English')`) in the switcher | `lib/pages/production_settings_page.dart:199` |
| U-11 | LOW | Favorites toggle is optimistic on feed cards but not on the Favorites page or car detail | |
| U-12 | LOW | No pull-to-refresh on car detail — stale after editing elsewhere | |

---

## 11. WHAT IS ACTUALLY DONE WELL (verified, with evidence)

Stated deliberately, because the audit is otherwise negative and these should not be regressed during remediation.

**Backend security**
1. `get_app_env()` defaults to `"production"` when unset, so a misconfigured deploy fails closed rather than running with DEBUG and dev secrets — `kk/config.py:17-20`.
2. `validate_required_secrets()` refuses to boot without `SECRET_KEY`, `JWT_SECRET_KEY`, `DATABASE_URL`, and explicitly rejects the known dev fallback values — `kk/config.py:22-45`.
3. `validate_upload_persistence()` refuses to boot in production if uploads would be ephemeral — a genuinely thoughtful guard against silent data loss on redeploy — `kk/config.py:100-127`.
4. `validate_redis_required()` pings Redis at boot and fails closed, so rate limits are never quietly per-process — `kk/config.py:130-167`.
5. OTPs are stored as HMAC-SHA256 (never plaintext), compared with `hmac.compare_digest`, expire in 10 minutes, and lock out after 5 attempts — `kk/routes/auth.py:172-177,1556-1564`.
6. JWT blocklist (Redis with DB fallback) plus refresh-token rotation that blacklists the old JTI, and replay returns 401 — `kk/routes/auth.py:385-419,582-627`.
7. Console SMS provider is hard-blocked in production — `kk/sms_service.py:209-212`.
8. Socket.IO query-string JWTs are blocked in production — `kk/socketio_handlers.py:_allow_socket_query_token`.
9. Upload magic-byte sniffing rejects extension spoofing on the multipart path — `kk/security.py:241-337`.
10. R2 attach uses an HMAC owner-prefixed object key, so a user cannot attach someone else's uploaded object — `kk/media_processing.py:43-69`.

**Authorization**
11. Consistent ownership checks: `_resolve_car_for_user` (`kk/routes/cars.py:1103-1107`), `_get_owned_search` (`kk/routes/saved_searches.py:37`), `resolve_job_owner` (`kk/routes/jobs.py:61-74`). **No IDOR was found on any mutation endpoint.**
12. Admin RBAC: 40+ routes each carry `@admin_required` **and** a `_deny(permission)` check; role changes, purges, and settings are super-admin only; admins cannot change their own role (`kk/routes/admin.py:1667`) or delete other admins (`:1974`).
13. Explicit field allowlist on car update — no mass assignment — `kk/routes/cars.py:1184-1218`.
14. Centralized listing visibility applied consistently across browse, detail, favorites, view history, and share pages — `kk/listing_visibility.py:37-42`.
15. Clients cannot self-publish: `status` is server-controlled and defaults to `pending` in production — `kk/listing_moderation.py:27-41`.
16. Listing contact phones are gated behind a separate rate-limited endpoint, with only a masked last-4 hint in the public payload.
17. admin-web uses **httpOnly cookies**, not `localStorage`, and actively clears the legacy `localStorage` token; the Next.js proxy returns 401 without a cookie.

**Infrastructure and observability**
18. Structured JSON logging with `X-Request-ID` propagation, Sentry with `send_default_pii=False`, and token-prefix-only redaction — `kk/logging_utils.py`, `kk/monitoring.py`.
19. Socket.IO auto-enables a Redis message queue in production and ties worker count to its presence; eventlet is explicitly disabled to avoid known 502s — `kk/app_factory.py:94-109`, `gunicorn.conf.py:13-15`.
20. Migration chain is clean and CI runs the upgrade twice against Postgres to prove idempotency — `scripts/ci_migration_smoke.py:46-48`.
21. Deep links verified live: `assetlinks.json` → `com.carzo.app`; AASA → `LN3R46L4H8.com.carzo.app` with `/listing/*`; `/health/push` → `fcm_ready: true`.
22. The team wrote its own launch gates — `publish_gate.py`, `verify_aab_signing.py`, `verify_production_host.py`, `verify_publish_ready.py` — and the Gradle guard that blocks debug-signed prod builds is exactly right.

**Flutter**
23. Release builds enforce HTTPS and refuse a non-TLS `API_BASE` — `lib/services/config.dart:103-124`.
24. Token refresh has a **single-flight guard** (`_refreshInFlight`), so concurrent 401s trigger one refresh, not a stampede — `lib/services/api/api_http.dart:343-356`.
25. `runZonedGuarded` + `FlutterError.onError` + a production-safe error widget; Sentry DSN via dart-define, not hardcoded — `lib/app/bootstrap.dart:58-91`.
26. Bootstrap does no blocking network I/O before `runApp`; heavy init is deferred to a post-frame microtask.
27. Global `ConnectivityBanner` plus disk cache and stale-while-revalidate on GETs — `lib/services/api/api_http.dart:32-63`.
28. Home feed has all of skeleton, empty, and error-with-retry states — `lib/features/home/home_feed_states.dart:53-106`.
29. **Zero** `TODO`/`FIXME`/`HACK` comments and zero dead `onPressed: () {}` handlers in 436 Dart files — unusually disciplined.
30. Locale is applied before the first frame, so there is no English/LTR flash for RTL users — `lib/app/bootstrap.dart:94-100`.
31. `avoid_print` is explicitly enabled and honoured (all remaining prints are `kDebugMode`-guarded).
32. Listing create is idempotency-keyed (`Idempotency-Key` header), and media upload retries 3× with server-side count verification and a resume path after app kill — `kk/routes/cars.py:898-911`, `lib/features/sell/sell_listing_media_upload.dart:203-256`.

---

## 12. PERFORMANCE ISSUES

| ID | Sev | Issue | Location |
|---|---|---|---|
| BE-01 | HIGH | Unbounded dealer listings query | `kk/routes/user.py:1066` |
| BE-02 | HIGH | N+1 on favorites / recently-viewed / analytics | `favorites.py:28`, `user.py:569`, `analytics.py:46` |
| D-03 | HIGH | No DB connection pool tuning | `kk/config.py:200-213` |
| BE-04 | HIGH | Synchronous FCM broadcast in request path | `kk/notification_broadcast.py:106` |
| P-01 | MEDIUM | Synchronous Roboflow plate-blur call (up to 60 s) inside the upload request | `kk/media_processing.py` |
| P-02 | MEDIUM | Video multipart upload reads the whole file (up to 100 MB) into memory | `kk/routes/media.py:161-168` |
| P-03 | MEDIUM | Facets endpoint runs ~10 DISTINCT scans per cache miss | `kk/routes/cars.py:487-501` |
| P-04 | MEDIUM | In-memory response cache is per-worker, so multi-worker deploys thrash | `kk/response_cache.py` |
| P-05 | LOW | Duplicative media stacks: `video_player`+`chewie`, `audioplayers`+`record` — larger binary | `pubspec.yaml` |
| P-06 | LOW | Client-side sort/filter fallbacks do work the server should do | `lib/features/home/home_fetch.dart:304-333` |

---

## 13. TESTING GAPS

**Measured baseline:** Flutter `275 passed / 43 failed` (318); `flutter analyze` 60 issues / 0 errors; `pytest kk/tests` 53 passed; backend factory smoke 79 tests (CI-only); `integration_test/` 1 trivial test.

### Manual tests required

| # | Test | Why |
|---|---|---|
| MT-01 | `POST /api/auth/signup` with only username+password against staging | Confirm C-01 and its fix |
| MT-02 | Send image via REST while recipient's socket is open | Confirm C-02 |
| MT-03 | Free-text search "Land Cruiser 2018" and inspect the outbound request | Confirm C-03 |
| MT-04 | Signed prod AAB install → chat, maps, image crop, push, deep links | Validate R8 with minimal ProGuard rules |
| MT-05 | `adb shell pm get-app-links com.carzo.app`; tap an HTTPS listing link on both platforms | Verify deep links on device |
| MT-06 | Send a push, tap it from foreground / background / killed | Push deep-link coverage |
| MT-07 | Airplane mode → home, car detail, chat send, sell submit | Offline UX incl. B-02 |
| MT-08 | Force-quit during sell media upload, then reopen My Listings | `SellPendingMediaResume` recovery |
| MT-09 | Two gunicorn workers + Redis, two clients on different workers | Socket.IO cross-worker delivery |
| MT-10 | Confirm Render has Redis, Celery worker, **and** beat provisioned | BE-13 — scheduled notifications |
| MT-11 | Full run with device locale `ar`, then `ku` (and `ckb`) | RTL, fonts, plurals, no format crash |
| MT-12 | Login → change password → retry the old access token | Confirm H-01 |
| MT-13 | Admin bans a user → user retries their existing access token | Confirm H-02 |
| MT-14 | Fetch a chat attachment URL logged out and as an unrelated user | Confirm C-10 |
| MT-15 | Upload a photo with a visible plate, with `ROBOFLOW_API_KEY` unset | Confirm M-08 fail-open |
| MT-16 | Delete an account with listings, chats, favorites, reports | Orphan rows (D-01) |
| MT-17 | Verify Google/Firebase API key restrictions in the Cloud console | M-11 |
| MT-18 | Presign an upload as `image/jpeg`, PUT HTML, then attach it | Confirm H-03 |

### Automated tests required

| # | Test | Layer | Catches |
|---|---|---|---|
| AT-01 | Signup without OTP issues no token | Backend | C-01 |
| AT-02 | REST send (all 5 endpoints) emits socket + push + notification | Backend | C-02 |
| AT-03 | Search query map includes `q` | Flutter | C-03 |
| AT-04 | Model↔migration drift check on SQLite **and** Postgres | CI | C-07, D-05 |
| AT-05 | 401 → refresh → retry, including single-flight under concurrency | Flutter | token regressions |
| AT-06 | Sell wizard E2E: form → POST → media upload → pending status | Integration | sell flow |
| AT-07 | Offline widget tests for banner, car detail, chat send | Flutter | B-02, B-08 |
| AT-08 | RTL golden tests for home, sell, settings in `ar` | Flutter | U-02 |
| AT-09 | Public `to_dict()` contains no PII (phone, email, exact GPS) | Backend | H-05 |
| AT-10 | Unapproved dealer profile returns 404 | Backend | H-04 |
| AT-11 | Concurrent favorite toggle and analytics increment | Backend | D-04 ✅ (`kk/tests/test_d04_atomic_counters.py`, `scripts/ci_migration_smoke.py::_d04_analytics_concurrency_smoke`), favorite-toggle concurrency still open under M-05 |
| AT-12 | Price round-trip exactness after the Numeric migration | Backend | C-11 |
| AT-13 | Chat attachment requires participant authorization | Backend | C-10 |
| AT-14 | Tokens revoked on password change and on ban | Backend | H-01, H-02 |
| AT-15 | Pagination caps enforced on every list endpoint | Backend | BE-01, BE-06 |
| AT-16 | `pytest kk/tests` wired into `backend_ci.yml` | CI | C-09 |

---

## 14. PRIORITIZED ROADMAP

### PHASE 0 — DECISION GATE (before any code)

Three product decisions determine the size of Phase 1. Answer them first.

1. **Reviews (C-04)** — build for v1, or descope? Full-stack, ~1–2 weeks.
2. **Payments / paid promotion (C-05)** — build for v1, or descope? If building, it must be IAP (StoreKit + Play Billing) with server-side receipt validation, ~2–3 weeks, and it changes store review.
3. **Search (C-03)** — this one is not optional. The backend is already built; wiring it is roughly 2–3 days.

Also settle: `LISTING_REQUIRE_APPROVAL` for launch, and whether the Docker path is supported or Render-only (affects C-08 priority).

---

### PHASE 1 — CRITICAL (ship blockers)

Nothing ships until every item here is closed.

| Order | ID | Task | Scope | Est. |
|---|---|---|---|---|
| 1 | C-01 | Delete the non-OTP signup branch; add OTP lockout; stop leaking exception text | Backend | 0.5 d |
| 2 | C-02 | Extract a shared `deliver_message()` (emit + push + notification) and call it from all 5 REST send endpoints | Backend | 1 d |
| 3 | C-10 | Private bucket + participant-scoped presigned GET for chat media; magic-byte validation; per-file size cap | Backend + infra | 2 d |
| 4 | C-06 | Create the upload keystore + `signing.properties`; wire Codemagic secrets; fix the GitHub CI AAB step; verify the App Links SHA | Config | 1 d |
| 5 | C-07 | Add the `pending_signup` migration (or delete the model); fix nullability drift; gate `create_all`/`legacy_schema` out of production | DB | 1 d |
| 6 | C-08 | `COPY tools/…` in the Dockerfile (or drop Docker as a supported path) | Config | 0.5 d |
| 7 | C-03 | Wire `q` into `homeFiltersToApiQuery` with debounce; verify the FTS trigger on prod Postgres | Frontend | 2–3 d |
| 8 | C-11 | Migrate price to `Numeric(12,2)` / integer cents with backfill | DB + BE + FE | 2 d |
| 9 | H-01, H-02 | Revoke all JTIs on password change, password reset, and ban (token-version claim) | Backend | 1 d |
| 10 | C-09 | Fix/quarantine the 43 failing tests; add `pytest` to CI; remove the `--skip-host` fallback; delete `analyze.txt` | Test + config | 2–3 d |
| 11 | AT-01…04 | Regression tests for every fix above | Test | 2 d |
| 12 | C-04, C-05 | Only if Phase 0 says build | Multiple | 3–5 wk |

**Phase 1 without reviews/payments: ~3 weeks.**

---

### PHASE 2 — HIGH (pre-launch hardening)

| ID | Task | Scope |
|---|---|---|
| H-03 | Validate presigned-upload content server-side (or lock the bucket policy) | BE + infra |
| H-04 | Require `dealer_status == "approved"` on the public dealer route | Backend |
| H-05 | Coarsen public dealer coordinates; expose exact only to the owner | Backend |
| H-06 | Make rate limiting fail **closed** in production | Backend |
| H-07 | Restrict or remove the plaintext-prefs token fallback | Frontend |
| D-01 | Explicit `ON DELETE` policies on all FKs | DB |
| D-02 | Remove `try/except` from the 3 silent migrations | DB |
| D-03 | Add `SQLALCHEMY_ENGINE_OPTIONS` (pool size, `pre_ping`, `recycle`) | Backend |
| D-04 | ✅ Done — replaced read-modify-write counters with atomic SQL (see §6 detail) | Backend |
| BE-01, BE-06 | Paginate dealer listings and `/api/my_listings` | Backend |
| BE-02 | Add eager loading to favorites, recently-viewed, analytics | Backend |
| BE-03 | Atomic claim (`UPDATE … WHERE status='pending' RETURNING`) for scheduled notifications | DB |
| BE-04 | Move broadcast fan-out to Celery | Backend |
| BE-05 | Clear `firebase_token` on permanent FCM failure | Backend |
| BE-13 | Provision and verify Celery worker + beat on Render | Ops |
| F-01, B-02 | Propagate `getCarDetail` errors; distinguish offline from not-found | Frontend |
| F-02 | Fail the build (not runtime) when `API_BASE` is missing | Frontend + CI |
| F-03 | Locale-aware `NumberFormat` in the TikTok card | Frontend |
| MI-01 | Blocked-users management screen | Frontend |
| MI-02 | `featured_until` + expiry beat job | DB + backend |
| MI-03, U-01 | `User.locale` column + `Accept-Language`; localize backend strings and the force-update gate | Multiple |
| B-01 | Link or remove the dead `AnalyticsPage` | Frontend |
| M-12 | Remove `?mode=developer` from production entitlements | Config |
| M-11 | Restrict Firebase/Maps API keys in the Cloud console | Config |
| MT-04, MT-05, MT-06, MT-11 | Device QA: R8 smoke, deep links, push, RTL | Manual |

**Estimated: ~2–3 weeks.**

---

### PHASE 3 — MEDIUM (post-launch, next release)

Security & correctness: M-01 (tighten `dev_code` gating), M-02 (uniform forgot-password response), M-04 (stop leaking exception text everywhere), M-05 (`bcrypt.init_app`), M-06 (image count cap + `MAX_IMAGE_PIXELS`), M-07 (lower `MAX_CONTENT_LENGTH`), M-08 (configurable fail-closed plate blur), M-09 (per-account login lockout), M-10 (auto-hide on report threshold).

Database: D-06 → D-09 (FK indexes, upsert races, `profile_picture` width, placeholder backfill cleanup). *(D-05 nullability drift resolved — see §6.)*

Backend/API: BE-07, BE-08 (bound saved-search payloads + fingerprint column), BE-09 (standardize response envelopes), BE-10 (narrow exception handling; add rollback and logging), BE-11 (unify the two view metrics), BE-12 (Celery fail-closed), BE-14 (remove no-op analytics endpoints), A-04 (single shared filter implementation).

Flutter/UX: F-04 → F-11 (`mounted` guards, AuthGuard timeout, cancellation, push diagnostics, `use_build_context_synchronously`, dead code, offline queue), B-03 → B-08, U-02 (directional icons), U-03 (ICU plurals for ar/ku), U-04 (bundle an Arabic fallback font), U-05 (migrate `_tr()` helpers to ARB), U-06 (`maxLines` overflow), U-08 (real search entry point).

Architecture: A-01 (remove or clearly quarantine `backend/`), A-02 (single schema path), A-03 (blueprint URL prefixes).

Performance: P-01 → P-04. Missing features: MI-04 → MI-09.

Tests: AT-05 → AT-16.

---

### PHASE 4 — LOW (polish)

L-01 → L-04, BE-15 → BE-20, F-12 → F-16, U-09 → U-12, D-10 → D-12, MI-10 → MI-12, P-05, P-06, A-05, A-06. Plus: pin the 6 unpinned Python dependencies, evaluate `video_thumbnail`, remove unused `mobile_scanner`/`geocoding`, consolidate `.env.example`, document `ROBOFLOW_*` and `FEATURE_FLAG_*`, fix the dead `ios-codemagic.yaml` trigger, reconcile `CHANGELOG.md` text-scale claims, add tablet screenshots.

---

### PHASE 5 — FINAL QA

**Gate 1 — Automated:** `flutter analyze` → 0 issues; `flutter test` → 0 failures; `pytest kk/tests` + factory smoke + migration smoke green in CI; `python scripts/publish_gate.py --with-flutter` passes; `pip-audit` clean.

**Gate 2 — Manual device QA:** all 18 MT items, on at least one low-end Android (API 24–26), one modern Android (14/15), and one iPhone; each in `en`, `ar`, and `ku`.

**Gate 3 — Security re-review:** re-verify C-01, C-10, H-01…H-07; attempt signup without OTP; attempt cross-user chat-media access; attempt IDOR on listing edit; confirm rate limits fail closed with Redis stopped.

**Gate 4 — Load/soak:** 100 concurrent browse requests (assert query counts, no N+1); 50 concurrent uploads; two-worker Socket.IO delivery; 24 h soak watching connection-pool exhaustion and memory.

**Gate 5 — Store submission:** signed AAB verified by `verify_aab_signing.py`; App Links fingerprint confirmed on device; iOS archive with the real Maps key and no `?mode=developer`; permission list matches actual features (remove the unused scanner); data-safety and privacy forms filled from `PrivacyInfo.xcprivacy`; account-deletion URL live; screenshots for all locales.

**Gate 6 — Rollback readiness:** database backup taken and a restore rehearsed; feature flags (`FEATURE_FLAG_CHAT`, `FEATURE_FLAG_SELL`) verified as working kill switches; Sentry alerting confirmed on both backend and app; `MIN_APP_VERSION` force-update path tested end to end.

---

## APPENDIX — Evidence and confidence

**Executed during this audit:** `flutter test` (275/43/318), `flutter analyze` (60 issues, 0 errors), `python -m pytest kk/tests -q` (53 passed), full Alembic upgrade on in-memory SQLite (42 revisions, clean), live HTTP probes of `carr-5hrm.onrender.com` (`/health`, `/health/push`, `/.well-known/assetlinks.json`, `/.well-known/apple-app-site-association`), `git ls-files` secret scan, `flutter pub outdated`.

**Independently re-verified by reading the source (not taken on trust):** C-01 (`kk/routes/auth.py:1698-1766`), C-02 (`emit_message_to_participants` appears exactly once in `kk/routes/chat.py`, at line 209), C-03 (only two `q` parameters in all of `lib/`, both unrelated), C-04 (no review model/route/UI), C-07 (`pending_signup` grep across all migrations), C-08 (`Dockerfile:18-23` vs `.dockerignore:27` vs `kk/r2_ops.py:29`).

**Marked UNKNOWN — requires a device, a Mac, or production access:** iOS archive viability; R8 runtime behaviour with minimal ProGuard rules; device deep-link tap-through; end-to-end push delivery; whether Render actually has Redis + Celery worker + beat provisioned; Google/Firebase API key restrictions; bcrypt work factor at runtime; Wi-Fi-without-internet behaviour; whether GitHub CI is currently green on `main`.

**Explicitly not trusted:** `car-listing-app-launch-checklist.md` marks 48 items `[x]`, several of which this audit could not confirm (crash reporting active in prod builds, analytics events firing, account deletion verified on device, no duplicate listings in feeds). `analyze.txt` is a stale 220-issue snapshot referencing a deleted `main_backup.dart`. `README.md:89-104` documents a dev proxy that is not the production architecture. `test/README.md:47` claims all tests use the fake API server; ~49 do not.
