# Legacy app shell

Production UI entry: `main_legacy.dart` → `MyApp` (used from `lib/main.dart`).

## Layout

| File | Role |
|------|------|
| `main_legacy.dart` | Imports, app shell, routing, shared widgets, galleries, search (~4.2k lines) |
| `home_page_legacy.dart` | Home feed, filters, listing grid |
| `saved_searches_legacy.dart` | Saved searches screen |
| `car_detail_legacy.dart` | Listing detail + spec cards |
| `sell_flow_legacy.dart` | Sell entry, drafts, steps 1–5, preview |
| `comparison_legacy.dart` | Car comparison screen |
| `auth_pages_legacy.dart` | Favorites, chat list, login, signup |
| `account_pages_legacy.dart` | Profile, settings, my listings, edit listing |

All `part` files share one library with `main_legacy.dart` (imports only in the main file).

## Analyzer

`lib/legacy/**` is included in `flutter analyze` (no folder exclude). **0 analyzer issues** (warnings and infos) as of the latest hardening pass.

## HTTP / ApiService

All legacy network I/O goes through `ApiService` (`lib/services/api_service.dart` and `lib/services/api/*`). Raw `http` calls were removed from legacy part files; token refresh and timeouts are centralized there.

## Refactor direction

Prefer new screens under `lib/pages/` and wire them in `MyApp` routes gradually. The modern `lib/pages/home_page.dart` is separate; `/` still uses legacy `HomePage` until parity is complete.

## Tooling

- `tools/split_legacy_part.py` — extract a 1-based line range into a new part file
- `tools/restore_legacy_parts_from_git.py` — recover a part from git `f353456` if a split goes wrong
