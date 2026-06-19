# Legacy app shell

Production UI entry: `main_legacy.dart` → `MyApp` (used from `lib/main.dart`).

## Layout

| File | Role |
|------|------|
| `main_legacy.dart` | Imports, app shell, routing, shared widgets, galleries, search (~3.9k lines) |
| `home_page_legacy.dart` | Legacy home feed + filters (`/legacy_home`, `/home_filters`) |
| `saved_searches_legacy.dart` | Saved searches screen |
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
| `/home_filters` | Legacy filter UI only |
| `/sell` | `SellPage` + draft gate |
| `/car_detail` | `CarDetailPage` |
| `/favorites`, `/profile`, `/settings` | Modern account pages |
| `/login`, `/signup`, `/forgot-password`, `/change-password` | Modern auth |
| `/my_listings`, `/edit_listing` | Modern listing management |
| `/comparison`, `/recently-viewed`, `/analytics`, `/saved-searches` | Modern utility pages |
| `/dealers`, `/dealer/profile`, `/dealer/edit` | Dealer directory + profile |
| `/chat`, `/chat/conversation`, `/notifications` | Modern chat |

## Legacy fallbacks

`/legacy_home`, `/legacy_sell`, `/legacy_car_detail`, `/legacy_favorites`, `/legacy_profile`, `/legacy_settings`, `/legacy_login`, `/legacy_comparison` — kept for rollback and smoke tests.

## Shared listing cards

Modern pages use `buildGlobalCarCard` and `mapListingToGlobalCarCardData` from `lib/pages/home_page.dart` (re-exported by `main_legacy.dart` for backward compatibility).

## Tooling

- `tools/split_legacy_part.py` — extract a 1-based line range into a new part file
- `tools/restore_legacy_parts_from_git.py` — recover a part from git `f353456` if a split goes wrong
