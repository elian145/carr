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

Shared helpers, listing cards, and galleries remain in `lib/app/carzo_shared.dart`. App shell and routes: `lib/app/production_app.dart` + `lib/app/production_routes.dart`.

Simplified **CarzoApp-only** stubs (migration smoke) are under `carzo_app/`.
