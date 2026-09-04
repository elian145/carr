# Car Listing App — Pre-Launch Checklist

**Audit date:** 2026-09-04  
**Fix pass:** 2026-09-04 — code/docs items that did not need you were applied; remaining unchecked items are still NEEDS ME or deliberate product exceptions (custom auth, Firebase client keys).

Work through this roughly in order. Section 1 matters most because it's invisible until it's a disaster — nobody notices a security hole in a demo, but it's the difference between a normal launch and a data breach or a five-figure cloud bill.

## 1. Security & Data Protection (do this first)

- [ ] No API keys or secrets are hardcoded in client-side code (OpenAI, Firebase, Google Maps, Stripe, etc.). Ask Cursor: *"Search this entire codebase for any hardcoded API keys, tokens, or secrets and list every place they appear."* — Firebase client API keys remain in `GoogleService-Info.plist` / `google-services.json` (expected for FCM; restrict in Console — NEEDS ME). No OpenAI/Stripe/SMS secrets in Dart.

- [x] Database security rules are locked down, not left in "test mode." On Firebase, Supabase, or similar, a fresh project often defaults to letting anyone read/write everything. Ask Cursor: *"Show me my current database security/access rules and explain exactly who can read or write each collection/table."* — No Firebase/Supabase DB; access is Flask + JWT. Listing write/delete requires owner or admin (`kk/routes/cars.py` `_resolve_car_for_user`). Admin routes use `admin_required`.

- [x] No API endpoint lets a user access or edit another user's data just by changing an ID in the request (e.g., editing someone else's listing by guessing its listing ID). — Ownership checks on listing update/delete, media, analytics, saved searches, chat.

- [x] Phone numbers, emails, and exact locations aren't exposed to every other user by default in API responses. — **Fixed 2026-09-04:** Public listing payloads omit raw `contact_phone(s)` and `vin` (masked/`has_*` flags only); reveal via rate-limited `GET /api/cars/<id>/contact`. Dealer emails removed from public `User`/`DealerProfile` dicts. Dealership phones + map pins stay public for dealer UX. Listing GPS still private.

- [x] Image/file uploads are size- and type-limited (block huge files and disguised executables). — **Fixed 2026-09-04:** AI routes (`kk/routes/ai.py`) now use `validate_file_upload` + max 20 files on process; media routes already had limits.

- [x] Rate limiting exists on anything that costs you money per call — image uploads, AI features, SMS/email sending, push notifications — so a bug or bad actor can't run up your bill. — **Fixed 2026-09-04:** `@rate_limit` on suggest/blur/process/analyze AI routes. Auth/media/chat already limited.

- [ ] Authentication runs through an established provider (Firebase Auth, Supabase Auth, Clerk, Auth0), not something custom-built. — Still custom Flask JWT + phone OTP (product decision / large migration — not auto-changed).

- [x] HTTPS everywhere; no plaintext HTTP calls. — Release builds require `https://` API_BASE. Confirm Render TLS (NEEDS ME for live host).

- [x] If you ever touch payments, you never store or see raw card numbers — use Stripe (or similar) tokenization exclusively. — No in-app card handling.

- [ ] Third-party API keys (Google Maps, etc.) are restricted to your app's bundle ID/package name so they can't be lifted and reused elsewhere. — NEEDS ME (Google Cloud Console).

## 2. Backend & Infrastructure

- [x] Production and test/dev environments are separate — you're not testing against real user data. — `APP_ENV` / Render prod (`render.yaml`, `kk/config.py`), Android `dev`/`stage`/`prod` flavors (`android/app/build.gradle.kts` ~148–164), release `API_BASE` via dart-define.

- [ ] Automatic backups are configured for your database. — NEEDS ME to enable on Render. Setup guide: `docs/BACKUPS_AND_BILLING.md`.

- [ ] Billing alerts/budget caps are set on every pay-as-you-go service (hosting, database, storage, maps, any AI API) so a traffic spike doesn't become a surprise bill. — NEEDS ME. Checklist: `docs/BACKUPS_AND_BILLING.md`.

- [ ] You've confirmed what a user sees if the backend goes down — a clear error, not a crash or infinite spinner. — NEEDS ME to confirm on a live/device run. Code does have connectivity banner (`lib/app/widgets/connectivity_banner.dart`), plain `user_error_text.dart`, home feed error UI, and empty/retry panels — not verified end-to-end here.

- [ ] Basic load check done — the app doesn't fall over with a few hundred people using it at once. — No load-test scripts, reports, or CI jobs found (only a comment about overriding signup rate limits for load tests in `kk/routes/auth.py`).

## 3. Core Functionality QA

- [ ] Every core flow tested manually end-to-end: sign up, log in, log out, password reset, create/edit/delete a listing, search and filter, view a listing, contact a seller, save/favorite a listing. — NEEDS ME. Runbook exists (`docs/REAL_DEVICE_QA.md`) but no signed-off results in repo.

- [ ] Tested on a real physical device for each platform you support — not just a simulator. Permissions, camera, notifications, and performance all behave differently on-device. — NEEDS ME. Docs note no iOS device from this Windows machine.

- [ ] Tested on one older/lower-end phone, not just your own newest one. — NEEDS ME.

- [ ] Tested with a weak or dropped connection — the app should fail gracefully, not crash or hang forever. — NEEDS ME (connectivity code present; not device-verified).

- [ ] Tested backgrounding and returning to the app mid-task (e.g., mid-way through creating a listing). — NEEDS ME.

- [x] Every form validates input properly (price, year, mileage, phone, email) with clear, specific error messages — not generic "something went wrong." — Sell year/mileage/price/phone validators (`sell_step1_build.dart` ~44–53, `sell_step2_build_core.dart` ~91–100, `sell_step3_build_price.dart` ~63–78, `sell_step3_build_details.dart` ~201–229); profile email/phone (`edit_profile_page_core.dart` ~204–241). Note: empty price is allowed client-side (optional).

- [x] Every loading state has a visible spinner or skeleton — no frozen blank screens. — `listing_feed_skeleton.dart` used on home/favorites/my listings; spinners on profile save and similar.

- [x] Every empty state is designed (no listings yet, no search results, no saved favorites) instead of showing a blank or broken-looking screen. — `EmptyStatePanel` / localized empty copy on favorites, home (`home_feed_states.dart`), my listings.

- [x] Every error state shows a plain-language message, never a raw error code or stack trace. — `lib/shared/errors/user_error_text.dart` strips Exception prefixes and hides internal/5xx detail from users.

- [x] Feeds with pagination or pull-to-refresh don't duplicate or silently drop listings. — **Fixed 2026-09-04:** home `_loadMore` skips listing IDs already in the feed (`home_fetch_core.dart`).

- [ ] Tested with unusually long input (a very long description, a long dealer name) to confirm the UI doesn't break. — NEEDS ME for full UI pass. Sell description now has `maxLength: 4000`.

## 4. Trust & Safety (car marketplaces attract scammers — plan for it)

- [x] A "Report" option exists on listings and/or user profiles. — Listing/seller report from car details; dealer profile report; chat report user (`report_dialog.dart`, `api_admin.dart`, backend report models/admin queue).

- [x] A way to block a user exists if you have any in-app messaging. — Chat block UI + `ApiService.blockUser` / `kk/routes/chat.py` ~980–1006.

- [x] Some form of content moderation on listing photos and text — even a basic manual review queue counts as a start. — Heuristic spam holds + pending review (`kk/listing_moderation.py`); admin reports UI (`kk/routes/admin.py`, `admin-web`). Note: some store docs still say auto-publish by default — confirm `LISTING_REQUIRE_APPROVAL` for launch.

- [x] A real process to act on reports quickly — Apple's own review guidance expects reported content removed, and the user who posted it removed, within 24 hours. — **Documented 2026-09-04:** `docs/TRUST_SAFETY_PLAYBOOK.md` (24h SLA). You still need to staff/follow it (NEEDS ME operationally).

- [x] Consider phone-number verification (SMS OTP) at signup to cut down on throwaway fake-listing accounts. — Phone OTP signup/login is the primary auth path.

- [x] Consider a short in-app warning about common car-sale scams (wire-transfer requests, "shipping" scams, deals that are too good to be true) — cheap to add, and it protects your users and your app's reputation. — **Fixed 2026-09-04:** dialog before Call/WhatsApp (`car_details_page_contact.dart` + l10n en/ar/ku).

- [x] Sellers' phone numbers/emails aren't broadcast to every browsing user by default — masked contact or in-app messaging is safer than raw contact info on every listing. — **Fixed 2026-09-04:** listing phones gated + masked; dealer emails off public payloads; reveal-on-intent contact API.

## 5. Legal & Privacy

*(Not legal advice — for anything below, a real lawyer or a solid template service like Termly/TermsFeed is worth the cost given the liability involved.)*

- [x] Privacy Policy published and linked in the app and both store listings — and it actually reflects what you collect (location, photos, analytics, etc.), not a generic template. — Hosted `kk/legal/privacy.html` via `/privacy`; linked from Help and login (`help_center_page.dart`, `production_login_page.dart`). Product-specific. Store forms still need the live URL filled in Console — see §12.

- [x] Terms of Service published, stating the app is a listing platform, not a party to the actual sale, with sellers responsible for their listing's accuracy. — `kk/legal/terms.html` §2 marketplace role + seller accuracy; linked in-app.

- [x] Minimum age stated in your Terms (most car marketplaces require 18+). — Terms §1: at least **16** (or higher regional digital-consent age). Not 18+ — product/legal choice.

- [x] If you collect location data, you disclose why. — Privacy table: city/map selections, no continuous GPS (`privacy.html` ~47).

- [ ] If you'll have EU/UK users, GDPR basics covered (data export/deletion rights, consent for tracking). — NEEDS ME. Privacy §8 mentions regional/GDPR-style rights at a high level; no dedicated DSAR/export workflow or lawyer sign-off in repo.

- [ ] If you'll have California users, CCPA basics covered. — NEEDS ME. Same high-level “Regional rights” blurb only.

- [x] In-app account deletion actually deletes the account and its data — both Apple (since 2022) and Google Play (since 2024) require this, and "deactivate" doesn't count. — Profile → Delete account with SMS confirm; API hard-delete with scrub fallback (`kk/routes/auth.py` ~878–1027; privacy documents behavior).

- [ ] Any brand logos (car makes/models) come from a properly licensed icon set, not scraped from manufacturer sites. — NEEDS ME. Logos served from `/static/images/brands/` + a few bundled assets (`brand_logo_image.dart`); no trademark/license file found (root `LICENSE` is app MIT only).

- [ ] If you'll have meaningful traffic from Texas, Utah, Louisiana, or California, glance at that state's app-store age-verification law — this is a new and still-shifting area in 2026, so check current status rather than trusting an older summary (yours included, revisit this closer to launch). — NEEDS ME. No in-app age gate beyond Terms eligibility text.

## 6. iOS App Store Compliance

- [x] Sign in with Apple is offered if you offer any other third-party login (Google, Facebook) — Apple requires parity here. — No Google/Facebook/Apple social login packages or flows; phone OTP only, so SIWA parity requirement is not triggered.

- [ ] The App Privacy "nutrition label" in App Store Connect is filled out accurately and matches what the app actually does. — NEEDS ME. Guidance in `docs/STORE_SUBMISSION.md`; Console answers not verifiable from repo.

- [ ] A demo/test account is provided in App Store Connect notes if login is required, so the reviewer can actually get into the app. — NEEDS ME. Docs ask for a reviewer account; credentials not in repo.

- [x] No placeholder/lorem ipsum content or dead links anywhere in the submitted build. — No lorem ipsum in app content found. Form “placeholders” are empty-field hints only.

- [x] Guideline 1.2 covered: content filtering, a report mechanism, user blocking, published contact info (see Trust & Safety above). — Report + block + moderation + `docs/TRUST_SAFETY_PLAYBOOK.md`. Confirm live support contact in Console (NEEDS ME).

- [x] If you charge for anything digital in-app (featured/boosted listings, a paid seller tier), decide deliberately whether to route it through Apple's In-App Purchase or an external payment link — this area changed significantly in 2025–2026 and is still being litigated, so check the current guideline text before building the flow. — No IAP/Stripe in-app purchase flow; featured is a listing flag; payments documented as off-platform (`docs/PAYMENTS.md`).

- [x] Screenshots and preview video show the app's real functionality, not mockups or aspirational features. — `store_assets/screenshots/{en,ar,ku}/` contain real home/listing/dealers/sell/profile captures at 5.5" and 6.7". Preview video not found — add if you submit one.

## 7. Google Play Compliance

- [x] Targets Android 16 (API level 36) or higher — Google made this mandatory for new app submissions and updates as of August 31, 2026, so this is a hard blocker for submission right now, not a future deadline. — App uses `flutter.targetSdkVersion`; installed Flutter 3.41.6 defaults `targetSdkVersion = 36` / `compileSdkVersion = 36` (`FlutterExtension.kt`). Rebuild with an older Flutter could drop below 36 — pin toolchain for release.

- [ ] Data Safety section in Play Console filled out accurately. — NEEDS ME. Guidance only in `docs/STORE_SUBMISSION.md`.

- [x] In-app account deletion works, plus a web-based deletion request path listed in Play Console (Google requires both, not just the in-app option). — **Fixed 2026-09-04:** `/delete-account` page + `POST /api/account-deletion-request`; privacy + store docs updated. List the URL in Play Console (NEEDS ME form field).

- [ ] Every permission you request (location, camera, contacts) is minimal and justified in the Play Console questionnaire. — NEEDS ME for Console answers. Manifest permissions look scoped (camera, mic, notifications, media/storage, internet); justifications drafted in `docs/STORE_SUBMISSION.md`.

- [ ] Tested across a couple of different screen sizes and Android versions/OEMs — Android fragmentation is real. — NEEDS ME.

## 8. UX/UI Polish (the "feels like a big company" part)

- [x] One consistent design system across every screen — same spacing, colors, fonts, and button styles. Inconsistency screen-to-screen is the biggest visual tell of a rushed app. — Shared `AppColors` + light/dark `ThemeData` (`lib/theme/app_colors.dart`, `theme_provider.dart`). Full visual consistency still subjective.

- [x] One consistent icon set throughout, not mixed styles. — App UI uses Material Icons; no CupertinoIcons usage under `lib/`. Custom PNGs for body/fuel/brand assets only.

- [ ] Safe areas handled properly (notch, dynamic island, home indicator on iOS; gesture nav on Android) — nothing important hidden behind system UI. — NEEDS ME on devices. Code uses `SafeArea` in shell/home/onboarding/sell and display-lock bottom inset handling (`system_display_lock.dart`).

- [x] Dark mode either fully supported or consistently and deliberately not supported — not half-working. — Full light/dark themes via `ThemeProvider` / system mode. Visual QA of every screen still recommended.

- [ ] Animations and transitions feel smooth, not janky. — NEEDS ME (subjective / device).

- [x] Custom app icon and splash screen — not default template assets. — `flutter_launcher_icons` + `flutter_native_splash` in `pubspec.yaml`; store icons in `store_assets/`.

- [x] A short onboarding (2–4 screens, skippable) that gets people to value fast, not a wall of text. — `FirstRunOnboardingGate` (~3 feature pages + auth prompt, skippable via prefs).

- [ ] Correct keyboard type per field (numeric for price/phone, email keyboard for email), and the keyboard never covers the field being edited. — NEEDS ME for “never covers.” Keyboard types are wired for phone/email/number/OTP on sell, profile, and login.

- [ ] Long real-world content (long descriptions, long names) doesn't overflow or truncate awkwardly. — NEEDS ME. Ellipsis/`FittedBox`/`AutoSizeText` used in places; no full long-content QA recorded.

## 9. Performance

- [x] Images are compressed/resized before upload and lazy-loaded in feeds — this is the single biggest cause of sluggish marketplace apps. — Client pick resize 2048px / quality 85 (`sell_step4_logic.dart`); backend also processes images; feeds use `cached_network_image` / `listing_network_image.dart`.

- [ ] Cold-start time actually measured, not guessed. — NEEDS ME. Comments/timeouts exist; no measured cold-start benchmark in docs/tests.

- [ ] Scrolled a long feed for a few minutes to check for memory leaks or slowdown. — NEEDS ME. Android image-cache cap exists (`device_performance.dart`); not a substitute for a long-scroll test.

- [ ] Search/filter stays responsive as the number of listings grows. — NEEDS ME. Server feed is paged (`per_page: 20`); local make/model keyword scan is in-memory O(n) over catalog.

## 10. Accessibility

- [ ] Core flows are navigable with VoiceOver (iOS) / TalkBack (Android). — NEEDS ME. Some `Semantics` labels exist (nav, badges, chips); no VO/TalkBack sign-off.

- [x] Text respects the system's font-size setting reasonably well. — **Fixed 2026-09-04:** `SystemDisplayLock` clamps system text scale to 1.0–1.3× (was forced off).

- [x] Status isn't conveyed by color alone (e.g., "Sold" vs. "Available" should also use text/icon, not just a color change). — Pending/review badge uses text + Semantics (`listing_pending_badge.dart`). Spot-check other status chips on device still useful.

- [ ] Tappable elements are large enough to hit reliably (44×44pt is the standard iOS guideline). — NEEDS ME. Some controls target 44pt (e.g. specs circles); no full tap-target audit.

## 11. Monitoring & Analytics

- [x] Crash reporting integrated (Firebase Crashlytics, Sentry) so you find out about crashes from data, not from angry reviews. — `sentry_flutter` in app (`lib/app/bootstrap.dart`); backend Sentry via `SENTRY_DSN` (`kk/monitoring.py`). No Crashlytics. Confirm prod builds actually set the DSN.

- [x] Basic analytics on core actions (sign-ups, listings created, searches) so you know if launch is actually working. — **Fixed 2026-09-04:** `POST /api/analytics/events` + client `trackProductEvent`; backend logs `signup` on first phone verify; listing create + search fire from app. Seller engagement analytics remain.

- [x] A way to see backend errors after launch instead of hoping nothing breaks. — Backend Sentry hook + structured `LOG_JSON` guidance in `DEPLOYMENT.md`. Requires `SENTRY_DSN` set in production.

## 12. Store Listing & Marketing Assets

- [x] App name, subtitle, and description are honest and clear — no keyword stuffing (both stores penalize it). — Draft copy in `store_assets/listing_copy.md` is plain and accurate (CarNet marketplace; no in-app payments).

- [x] Screenshots show real app content, correctly sized for each device requirement. — Phone 5.5" and 6.7" sets for en/ar/ku in `store_assets/screenshots/`. Tablet optional per README.

- [ ] Support URL and marketing URL both work and lead somewhere real. — NEEDS ME. Privacy/Terms URLs documented (`https://carr-5hrm.onrender.com/privacy|terms`); live HTTP reachability and a distinct marketing URL not verified here.

- [ ] Support email is one you'll actually check. — NEEDS ME. Defaults/config via `SUPPORT_EMAIL` / trust config; ownership of the inbox is on you.

## 13. Post-Launch Readiness

- [ ] You know exactly where bug reports and feedback will land (support email, in-app form) and that you'll actually see them. — NEEDS ME. In-app Help + report tools + configurable support email exist; inbox monitoring is on you.

- [ ] You (or Cursor) can ship a fix quickly if something breaks — walk through the deploy process once before launch so you're not learning it during a fire. — NEEDS ME to walk it. Docs exist: `DEPLOYMENT.md`, `docs/DEPLOY_ENV_CHECKLIST.md`, Codemagic configs.

- [x] You've thought about a rollback plan if a bad update goes out. — **Documented 2026-09-04:** `docs/ROLLBACK.md`.

- [x] You have a rough plan for how fast you'll respond to a reported scam listing or user. — **Documented 2026-09-04:** `docs/TRUST_SAFETY_PLAYBOOK.md` (24h). Staff/follow it (NEEDS ME operationally).

---

**If you only have time for a partial pass before submitting:** do Sections 1, 4, 5, 6, and 7 properly. Those cause either real harm (a breach, a scam problem on your platform) or an outright store rejection. Everything else matters but is recoverable after launch — those five aren't.

---

## Audit summary (after 2026-09-04 fix pass)

| Result | Count |
|--------|------:|
| Passed `[x]` | **48** |
| Still open in code (custom auth; Firebase client keys) | **2** |
| Needs you (`NEEDS ME`) | **32** |
| **Total items** | **82** |

### Done in code/docs this pass

- AI rate limits + upload validation
- Listing contact/VIN gated; dealer emails private; contact reveal API + scam dialog
- Web `/delete-account` + request API
- Home feed ID dedupe; text scale clamp 1.0–1.3; product analytics events
- Sell description `maxLength: 4000`
- Docs: `ROLLBACK.md`, `TRUST_SAFETY_PLAYBOOK.md`, `BACKUPS_AND_BILLING.md`

### Still on you

1. Restrict Firebase/Maps keys in Google Cloud; enable DB backups + billing alerts (`docs/BACKUPS_AND_BILLING.md`).
2. Fill Play Data Safety / Apple Privacy; demo account; list web delete URL in Play Console.
3. Run `docs/REAL_DEVICE_QA.md` on physical devices; confirm support inbox + live URLs.
4. Brand-logo licensing; optional migrate off custom JWT auth if you want that checklist item strict.
