# Legacy app shell

Production entry: `lib/main.dart` → [ProductionApp] (`lib/app/production_app.dart`).

Legacy library: `main_legacy.dart` — widgets, galleries, and embedded legacy UI still used by `/legacy_home`.

## Layout

| File | Role |
|------|------|
| `main_legacy.dart` | Imports, shared widgets, galleries, search (~2.7k lines) |
| `home_page_legacy.dart` | Legacy home feed (`/legacy_home`) |
| `saved_searches_legacy.dart` | Legacy saved searches (embedded from legacy home) |
| `car_detail_legacy.dart` | Legacy listing detail (unused by routes; kept for reference) |
| `sell_flow_legacy.dart` | Legacy sell flow (unused by routes; kept for reference) |
| `comparison_legacy.dart` | Legacy comparison (unused by routes) |
| `auth_pages_legacy.dart` | Legacy favorites/login (unused by routes) |
| `account_pages_legacy.dart` | Legacy profile/settings (unused by routes) |

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

## Legacy fallback aliases

Defined in `lib/legacy/legacy_fallback_routes.dart` for smoke tests and rollback URLs.

| Route | Screen |
|-------|--------|
| `/legacy_home` | `LegacyHomePage` (only non-modern fallback) |
| `/legacy_home_filters` | `HomeFiltersPage` |
| `/legacy_sell` | Modern `SellPage` + draft gate |
| `/legacy_car_detail` | `CarDetailPage` |
| `/legacy_favorites` | `FavoritesPage` |
| `/legacy_profile` | `ProfilePage` |
| `/legacy_settings` | `SettingsPage` |
| `/legacy_login` | `LoginPage` |
| `/legacy_comparison` | `ComparisonPage` |
| `/legacy_saved_searches` | `SavedSearchesPage` |

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
