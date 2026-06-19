# Legacy app shell

Production entry: `lib/main.dart` → [ProductionApp] (`lib/app/production_app.dart`).

Legacy library: `main_legacy.dart` — widgets, galleries, and `/legacy_*` fallback routes via [buildLegacyFallbackRoutes].

## Layout

| File | Role |
|------|------|
| `main_legacy.dart` | Imports, app shell, routing, shared widgets, galleries, search (~3.1k lines) |
| `home_page_legacy.dart` | Legacy home feed + filter UI fallback (`/legacy_home`, `/legacy_home_filters`) |
| `saved_searches_legacy.dart` | Saved searches fallback (`/legacy_saved_searches`) |
| `car_detail_legacy.dart` | Listing detail (`/legacy_car_detail`) |
| `sell_flow_legacy.dart` | Sell flow (`/legacy_sell`) |
| `comparison_legacy.dart` | Car comparison (`/legacy_comparison`) |
| `auth_pages_legacy.dart` | Legacy favorites, login, signup fallbacks |
| `account_pages_legacy.dart` | Legacy profile, settings fallbacks |

All `part` files share one library with `main_legacy.dart` (imports only in the main file).

## Production routes (modern)

| Route | Screen |
|-------|--------|
| `/` | `HomePage` |
| `/home_filters` | `HomeFiltersPage` (brand/model/city + more-filters sheet) |
| `/sell` | `SellPage` + draft gate |
| `/car_detail` | `CarDetailPage` |
| `/favorites`, `/profile`, `/settings` | Modern account pages |
| `/login`, `/signup`, `/forgot-password`, `/change-password` | Modern auth |
| `/my_listings`, `/edit_listing` | Modern listing management |
| `/comparison`, `/recently-viewed`, `/analytics`, `/saved-searches` | Modern utility pages |
| `/dealers`, `/dealer/profile`, `/dealer/edit` | Dealer directory + profile |
| `/chat`, `/chat/conversation`, `/notifications` | Modern chat |

## Legacy fallbacks

`/legacy_home`, `/legacy_home_filters`, `/legacy_sell`, `/legacy_car_detail`, `/legacy_favorites`, `/legacy_profile`, `/legacy_settings`, `/legacy_login`, `/legacy_comparison`, `/legacy_saved_searches` — kept for rollback and smoke tests.

## Shared modules (modern home filters)

- `lib/shared/home/home_filter_fields.dart` — filter state + persistence
- `lib/shared/home/home_filter_options.dart` — static option lists
- `lib/shared/home/home_more_filters_sheet.dart` — secondary filters sheet
- `lib/shared/home/home_active_filter_chips.dart` — active chip UI

## Shared listing cards

Modern pages use `buildGlobalCarCard` and related helpers from `lib/shared/listings/global_listing_card.dart` (re-exported by `main_legacy.dart` for backward compatibility).

## CarzoApp (refactor shell)

`lib/app/routes.dart` mirrors modern production routes for migration testing via `CarzoApp`.

Production routing lives in `lib/app/production_routes.dart` (`buildProductionRoutes()`). Legacy fallbacks are in `lib/legacy/legacy_fallback_routes.dart` (`buildLegacyFallbackRoutes()`), merged in [ProductionApp].

Shared shell: `lib/app/app_shell.dart` (`CarNetAppShell`) — used by [ProductionApp] and [CarzoApp].

Shared auth: `lib/shared/auth/auth_guard.dart` (`AuthGuard`, `SellAuthPrompt`).

## Tooling

- `tools/split_legacy_part.py` — extract a 1-based line range into a new part file
- `tools/restore_legacy_parts_from_git.py` — recover a part from git `f353456` if a split goes wrong
