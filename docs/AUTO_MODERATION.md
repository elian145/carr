# Automated listing moderation: operations, release, rollback

The engine lives in `kk/auto_moderation/`; the dashboard is **Auto moderation**
in admin-web. It decides, for every new listing and every submitted edit of a
published listing, one of `AUTO_APPROVE`, `NEEDS_REVIEW` or `HOLD`. It never
rejects anything. **It ships in shadow mode: it records what it would have
done and publishes nothing.** Live auto-approval is NOT enabled by this
release and cannot be enabled without several deliberate server-side steps
(see "Enabling live mode later").

## Guarantees that hold in every mode

* Nothing is auto-approved unless **every** mandatory check passes, the seller
  is proven (an approved dealer, or has listings a human approved earlier;
  automatic approvals never count towards that), and no signal is uncertain.
* **Payment**: a listing that requires payment is never auto-approved unless a
  server-side payment verifier returns proof for *that* listing (below).
* **Media**: failed, missing, processing or unverified media is never
  approved. The declared cover must be an attached image and must itself have
  been inspected. Videos are never inspected by the AI, so a listing with an
  unapproved video goes to review.
* **AI check**: required for every auto-approval and checked again at the
  moment of publication. It cannot be turned off from the dashboard or the
  API; only the server operator can (`AUTO_MODERATION_ALLOW_RULES_ONLY=1`,
  not recommended).
* The AI is advisory. Its verdict is not proof of ownership, authenticity or
  condition.
* A human acting first always wins; a result for content the seller has since
  changed is discarded; the kill switch is strictly ordered against
  in-flight approvals (PostgreSQL row lock: an approval that already passed the
  check finishes first, the next one is blocked).
* Duplicate Celery tasks decide and publish once (unique key
  `(subject, content token, mode)`, compare-and-set claims).

## Shadow mode when no AI provider is configured (today's production state)

With no provider configured and the AI check required (the default):

* Every evaluated listing is recorded as `NEEDS_REVIEW` with reason
  `ai_not_configured`. Rule-level findings (new seller, scam wording,
  duplicates ...) are recorded as well.
* Shadow mode therefore **cannot measure how often automation would approve**.
  The Overview tab says so in plain words ("Can anything be auto-approved right
  now? No", with the blocker `No AI provider is configured`).
* The shadow-mode comparison with admin decisions stays empty of
  `would_approve` rows, so the live-mode gate cannot pass.
* Nothing can be approved without the AI check: `rules.ai_signals` blocks it at
  decision time and `engine._ai_gate` blocks it again at apply time.

Use shadow mode with an AI provider configured to collect the evidence needed
before live mode is even considered.

## Configuring a real AI provider (server environment only)

| Variable | Meaning |
|---|---|
| `AUTO_MODERATION_AI_PROVIDER` | `openai` or `anthropic` (`none` = disabled; `stub` only works when `APP_ENV` is `testing`) |
| `AUTO_MODERATION_AI_MODEL` | model name for that provider (required for `anthropic`; recommended for `openai`) |
| `AUTO_MODERATION_OPENAI_API_KEY` | key (falls back to `OPENAI_API_KEY`) |
| `AUTO_MODERATION_ANTHROPIC_API_KEY` | key for Anthropic |

Check the Overview tab afterwards: "AI provider: <name> (<model>)" without
"not configured". Keys are never returned by any endpoint. Choose the model and
set a **billing limit in the provider's console**; this code has no
currency-based budget.

### Image coverage

* Photos are sent in batches of `ai.max_images` (default 4, range 1-10) and
  **every** photo is inspected, up to `ai.max_total_images` (default 12, range
  1-40) per listing. The cover is first in the first request.
* A listing with more photos than `max_total_images` is **not** partially
  inspected: no AI call is made and it goes to review (`too_many_images`).
* If any batch fails, times out or returns a verdict for fewer photos than
  requested, the listing goes to review (never approval). Result fields:
  `images_expected`, `images_checked`, `cover_checked`, `calls`.
* Only `https://` photo URLs are sent; with `ai.send_images` off nothing is
  uploaded and no listing can be approved (coverage is incomplete).

### Spend controls

| Control | Default | Effect |
|---|---|---|
| `ai.only_if_candidate` | on | the AI is called only when every deterministic rule already passes; flagged listings cost nothing |
| `ai.max_total_images` / `ai.max_images` | 12 / 4 | at most `ceil(photos / max_images)` requests per evaluation (3 by default); over-limit galleries cost nothing |
| `ai.timeout_seconds` | 20 | per request; one evaluation stops after 3x this |
| `retry.max_attempts` | 5 | each *retry* of a failed evaluation calls the provider again: worst case is attempts x requests per listing |
| Content token | | an unchanged listing is evaluated once; duplicates and re-deliveries reuse the recorded decision |
| Mode off / kill switch | | no AI calls at all |

A rough ceiling per listing is `max_attempts x ceil(max_total_images / max_images)`
requests, each carrying at most `max_images` photos. Estimate cost with your
provider's current price list; none is assumed here.

## Payments

CarNet has **no payment system** (see `docs/PAYMENTS.md`): there is no ledger,
no paid-listing state and no free-allowance counter. Therefore:

* `listing_payment_required` defaults to **off**: today every listing is
  "free" and payment does not gate anything.
* If an operator turns it **on** without a verifier, nothing is auto-approved
  (`payment_unverifiable` -> review, and the readiness panel lists
  `payment_verifier_not_registered`). No success is ever invented.
* Smallest safe integration when billing exists: implement a function in the
  billing module and register it once at startup:

  ```python
  from kk.auto_moderation.payment import register_payment_verifier

  def verify(subject_type, car_id, seller_id):
      # Look up YOUR ledger. Return None unless there is proof for this car.
      row = Ledger.query.filter_by(car_id=car_id, settled=True).first()
      if row:
          return {"status": "paid", "car_id": car_id, "reference": row.reference}
      if FreeAllowance.consume_preview(seller_id):      # no side effects here
          return {"status": "free_allowance", "car_id": car_id, "reference": "allowance-<id>"}
      return None

  register_payment_verifier(verify)
  ```

  The proof must say `paid` or `free_allowance`, carry the same `car_id` and a
  non-empty `reference`. Anything else (None, wrong car, missing reference, an
  exception) is *unverified* and sends the listing to review (an exception
  holds and retries). The verifier must be read-only: it is called at decision
  **and** again at publication time.

## Admin permissions

* `auto_moderation.read` and engaging the kill switch: `super_admin`, `moderator`.
* Releasing the kill switch and changing settings: `super_admin`.
* Overriding a decision (approve / revoke / pin to review) reuses
  `listings.write`.
* Every other role gets no navigation entry, no page and HTTP 403 from the API.

## Environment summary

| Variable | Default | Meaning |
|---|---|---|
| `AUTO_MODERATION_DISABLED=1` | unset | hard off |
| `AUTO_MODERATION_KILL_SWITCH=1` | unset | forced kill switch (cannot be released from the UI) |
| `AUTO_MODERATION_ALLOW_LIVE=1` | unset | **required for live mode; leave unset** |
| `AUTO_MODERATION_ALLOW_RULES_ONLY=1` | unset | lets a server operator lift the AI requirement; never from the dashboard; not recommended |
| `AUTO_MODERATION_ALERT_EMAILS`, `AUTO_MODERATION_TELEGRAM_BOT_TOKEN`, `AUTO_MODERATION_TELEGRAM_CHAT_ID`, `ADMIN_WEB_BASE_URL` | unset | alerts (no PII in them) |

## Enabling live mode later (not part of this release)

All of: `AUTO_MODERATION_ALLOW_LIVE=1` on the server; a configured AI provider;
no kill switch; the shadow-mode gate passed on **your own** measured
admin-vs-automation data (minimum sample and maximum unsafe-approval rate are
operator policy, not accuracy claims); a super_admin saving `mode=live` with
`confirm_live`. Do none of this until shadow data from a real AI provider has
been reviewed.

## Two-stage release

Production today: code `7abed07`, Alembic head `u9v0w1x2y3z4`.
`start_render.sh` runs `python -m flask db upgrade` before gunicorn
(`set -e`), and **code that does not know the database's Alembic head cannot
start**. Rehearsed on PostgreSQL 17: after the new migration is applied,
`7abed07` fails both `flask db upgrade` and app import with
`Can't locate revision identified by 'v0w1x2y3z4a5'`. Hence two stages.

| Stage | Branch | Commit | Contents |
|---|---|---|---|
| 0 | production | `7abed07` | current code, head `u9v0w1x2y3z4` |
| 1 bridge | `release/auto-moderation-bridge` | `65f3a58` | `7abed07` + migration `v0w1x2y3z4a5` (+ the head assertion in `test_listing_revisions.py`). **No application change.** |
| 2 full release | `feature/auto-moderation` | tip of the branch (a descendant of the bridge) | engine, tasks, admin API, admin-web, docs |

The migration is byte-identical in both branches. It is purely additive (two
new tables `listing_moderation_run` / `listing_moderation_event`, all foreign
keys `ON DELETE SET NULL` except event -> run), needs no backfill, and sets
`lock_timeout = '5s'` so that if a long write transaction holds `car`,
`car_revision` or `user`, the migration **fails fast** instead of queueing
every other write behind its DDL.

### Before starting

1. Take (or confirm) a database backup / restore point.
2. Confirm production `alembic_version` is `u9v0w1x2y3z4` and the running code is `7abed07`.
3. Do not set `AUTO_MODERATION_ALLOW_LIVE`, `AUTO_MODERATION_KILL_SWITCH`, or any AI key yet.

### Stage 1: bridge

1. Deploy `release/auto-moderation-bridge` to the **backend** only. Let a single
   instance run `flask db upgrade` (three concurrent upgrades were observed to
   end with one head and one set of tables on PostgreSQL 17, but keep it to one).
2. Verify:
   ```sql
   select version_num from alembic_version;            -- v0w1x2y3z4a5
   select to_regclass('listing_moderation_run'), to_regclass('listing_moderation_event');
   ```
   and that the service is healthy and listings, search and admin pages behave as before.
   If the migration reports a lock timeout, nothing was applied: simply deploy
   again (`set -e` in `start_render.sh` aborts the new instance before gunicorn
   starts; Render keeps serving the previous instance when a deploy fails to start).
3. Leave the bridge running until you are confident (it is a complete, working
   release: it behaves exactly like `7abed07` and ignores the new tables).

### Stage 2: full release

1. Deploy `feature/auto-moderation` to **backend, Celery worker and Celery beat**
   (the beat schedule gains `sweep-listing-moderation`, every 120 s) and admin-web.
   `flask db upgrade` is a no-op.
2. Verify: Overview tab shows **Effective mode: Shadow**, "Can anything be
   auto-approved right now? No", kill switch released; the Decisions tab starts
   filling as sellers post. Nothing is published by automation.
3. If the new code misbehaves, press the **kill switch** (instant, no deploy).

### Rollback

* **The rollback target is the bridge, never `7abed07`.** `7abed07` cannot start
  once the database is at `v0w1x2y3z4a5`.
* Redeploy `release/auto-moderation-bridge`. Nothing in the database needs to
  change: rehearsed on PostgreSQL 17 with moderation records present, the bridge
  runs `flask db upgrade` (no-op), boots, serves, and can even hard-delete a
  listing that has moderation history (the foreign keys null the link; the
  decision rows stay).
* **Do not run `flask db downgrade` in production and do not delete moderation
  records.** They are the audit trail and the shadow-mode evidence. Rolling
  forward again restores everything.
* While on the bridge there is no automated decision-making and the Auto
  moderation page is unavailable; listings are reviewed manually as before.

## Known limitations

* No payment system exists, so payment can only ever be "not required" or
  "needs a verifier" (above).
* Videos are never inspected; a listing with an unapproved video goes to review.
* The AI sees photos and text only; it cannot verify identity, ownership,
  odometer or VIN, so those stay human decisions.
* Without an AI provider, shadow mode cannot show what automation would approve.
* No currency-based spend cap exists; use the controls above plus the provider's own limit.
* The settings-row kill-switch ordering relies on the settings row existing,
  which is always true once live mode has been saved.
* Automatic approval of edits to published listings re-uses the same checks;
  identity changes (brand/model/year/VIN) and large price changes always need review.

## Tests

* `kk/tests/test_auto_moderation_rules.py`, `kk/tests/test_auto_moderation_engine.py`: SQLite, run in CI.
* `kk/tests/test_auto_moderation_postgres.py`: real concurrency on PostgreSQL;
  skipped unless `CARNET_PG_TEST_URL` is set (local server only; the database is
  dropped and re-created; also needs `CARNET_PG_TEST_CONFIRM_DISPOSABLE=1`).
  Set `CARNET_PG_TEMPLATE_DB` to a database holding the production-head schema
  to also rehearse the migration from `u9v0w1x2y3z4`.
* `admin-web/e2e/auto-moderation.spec.ts` (+ `seed_auto_moderation.py`):
  authenticated browser test of permissions, settings, the kill switch and the
  decision history, against a throwaway backend.
