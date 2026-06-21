# Production UI (part library)

Production screens live here as a single Dart library (`carzo_pages.dart` + `*_part.dart` files).

Entry: `lib/main.dart` → `MyApp` from `lib/app/production_app.dart`.

## Layout

| File | Role |
|------|------|
| `carzo_pages.dart` | Imports, app shell, routing, shared widgets, galleries, search (~3.4k lines) |
| `home_page_part.dart` | Home feed, filters, listing grid |
| `saved_searches_part.dart` | Saved searches screen |
| `car_detail_part.dart` | Listing detail + spec cards |
| `sell_flow_part.dart` | Sell entry, drafts, steps 1–5, preview |
| `comparison_part.dart` | Car comparison screen |
| `auth_pages_part.dart` | Favorites, chat list, login, signup |
| `account_pages_part.dart` | Profile, settings |
| `legacy_routes_part.dart` | Optional `/legacy_*` rollback routes for tests |

All `part` files share one library with `carzo_pages.dart` (imports only in the main file).

## Shared shell exports

Other pages import listing cards and bottom nav via `lib/app/listing_shell.dart` (re-exports from this library).

## Refactor direction

Extract individual screens from part files into standalone `lib/pages/*.dart` files over time. Simplified duplicates (e.g. `lib/pages/home_page.dart`) are used by `CarzoApp` smoke tests until each screen is fully extracted.

## Tooling

- `tools/split_legacy_part.py` — extract a 1-based line range into a new part file
- `tools/restore_legacy_parts_from_git.py` — recover a part from git history if a split goes wrong
