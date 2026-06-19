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

## Refactor direction

Production `/` uses modern `HomePage`; `/sell` uses modern `SellPage`; `/car_detail` uses modern `CarDetailPage`. Legacy screens remain at `/legacy_home`, `/legacy_sell`, and `/legacy_car_detail`.

## Tooling

- `tools/split_legacy_part.py` — extract a 1-based line range into a new part file
- `tools/restore_legacy_parts_from_git.py` — recover a part from git `f353456` if a split goes wrong
