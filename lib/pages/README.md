# Pages

Production screens live as **`part of '../app/carzo_shared.dart'`** under this folder:

| File | Screen(s) |
|------|-----------|
| `home_page.dart` | Home feed, filters, listing grid |
| `sell_flow_page.dart` | Sell entry, drafts, steps 1–5 |
| `car_details_page.dart` | Listing detail (`CarDetailsPage`) |
| `saved_searches_page.dart` | Saved searches |
| `comparison_page.dart` | Car comparison (`CarComparisonPage`) |
| `production_auth_pages.dart` | Favorites, chat list, login, signup |
| `production_account_pages.dart` | Profile, settings |

Shared helpers and the part-library host remain in `lib/app/carzo_shared.dart`. Listing cards, galleries, and the home search dialog are standalone modules under `lib/app/widgets/` (re-exported from `listing_shell.dart`). App shell and routes: `lib/app/production_app.dart` + `lib/app/production_routes.dart`.

Simplified **CarzoApp-only** stubs (migration smoke) are under `carzo_app/`.
