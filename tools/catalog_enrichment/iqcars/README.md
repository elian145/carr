# IQ Cars catalog extraction (candidate data only)

Read-only tooling that collects the **publicly served** IQ Cars catalog (`cp.iqcars.net/api`, the same unauthenticated
`publicCar/...` calls the Android app `com.redfoxpro.iqcars` makes) and compares it with CarNet.
It is **not connected** to the app, `assets/`, `lib/` or any backend.

## Scope
Brand, model, trims, engine sizes, cylinders. Nothing else is claimed (no transmission/drivetrain/seats/hp/torque/body).

## Pipeline

| Step | Command (repo root) | Network | Output |
|---|---|---|---|
| 1. fetch used-car per-model lists | `python tools/catalog_enrichment/iqcars/extract_iqcars.py bulk --confirm-bulk --delay 4` | yes, 1 req/model, cache-first, resumable | `raw/cache/*.json` (verbatim) |
| 2. fetch brand-new catalog | `... extract_iqcars.py new-cars --confirm-bulk --delay 4` | yes, ~59 req | `raw/cache/*.json` |
| 3. assemble RAW artifact | `... extract_iqcars.py assemble` | no | `raw/iqcars_catalog.json` |
| 4. normalize | `python tools/catalog_enrichment/iqcars/normalize.py` | no | `generated/iqcars_model_options.json`, `generated/iqcars_brand_new_exact_configs.json` |
| 5. compare with CarNet | `python tools/catalog_enrichment/iqcars/compare_carnet.py` | no | `generated/iqcars_model_matching_report.json`, `iqcars_vs_carnet_comparison.json`, `iqcars_coverage_report.json` |

Tests: `python -m pytest tools/catalog_enrichment/iqcars/tests -q`

## Data semantics (important)
* **Used-car catalog = MODEL-LEVEL, INDEPENDENT lists** per model: `trims[]`, `engines[]`, `cylinders[]`.
  IQ does **not** link trim -> engine -> cylinder there. Nothing in this folder invents those links.
* **Brand-new catalog** (~58 curated models) *does* publish exact trim -> engine -> cylinder rows. They live in their own file and are
  never merged into the model-level lists. Agreement/conflict with the used-car lists is recorded, never auto-resolved.
* **Raw stays raw**: `raw/iqcars_catalog.json` keeps every response key (incl. `SeatNumbers`, `Specifications`), raw trim strings
  (stray whitespace included), IQ IDs, year ranges and ar/ku names.
* **Trim normalization is safe-only**: NFKC, trim, collapse spaces, exact-duplicate removal. `EX.R` vs `EXR` or `Twin-Turbo` vs
  `Twin Turbo` are flagged `POSSIBLE_DUPLICATES` and stay separate.
* **Engines**: `4.5TD` -> displacement `4.5L` + qualifier `TD` (qualifiers always kept). Cylinders are never inferred from displacement.
* **Model identity** = IQ model IDs; matching to CarNet uses `model_boundaries.ModelIndex` exact identity only.
  Near-siblings (e.g. `Land Cruiser FJ` vs `Land Cruiser`) are reported as ambiguous, never forced.

## Request etiquette / safety
GET only, no auth/tokens/cookies, one persistent connection, >= 0.5 s floor (use >= 1.5 s; 4 s was used for the main run),
cache-first (a cached success is never requested again), stop on 401/403/429/5xx/network errors (no retry, no workaround),
every request logged in `raw/request_log.jsonl`, every run summarised in `raw/run_summaries.jsonl`.
Delete a cache file only if you deliberately want a fresh copy.

## Candidate overlay (not connected to the app)

`python tools/catalog_enrichment/iqcars/build_overlay.py` (offline, read-only on assets/raw) writes `generated/carnet_iqcars_overlay_*.json` (+ samples `.md`).
Additive, model-level only; ambiguous/unmatched/explicitly excluded models never enter it; lookalike trims are held for review; IQ's identical full-list defaults (139 engines / 10 cylinder counts shared by dozens of unrelated models) are excluded as non-model-specific. See the docstring of `build_overlay.py` for the rules.
