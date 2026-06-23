# Pages

Production screens live as **`part of '../app/carzo_shared.dart'`** or standalone modules:

| File / folder | Screen(s) |
|---------------|-----------|
| `features/home/home_page.dart` | Home feed, filters, listing grid |
| `features/sell/sell_*.dart` | Sell entry, drafts, steps 1–5 |
| `pages/car_details_page.dart` | Listing detail (`CarDetailsPage`) |
| `pages/saved_searches_page.dart` | Saved searches |
| `pages/comparison_page.dart` | Car comparison (`CarComparisonPage`) |
| `pages/production_auth_pages.dart` | Favorites, chat list, login, signup |
| `pages/production_account_pages.dart` | Profile, settings |
| `features/chat/chat_pages.dart` | Chat list + conversation (standalone) |

Shared helpers and the part-library host remain in `lib/app/carzo_shared.dart`. Listing cards, galleries, and the home search dialog are under `lib/app/widgets/`. App shell and routes: `lib/app/production_app.dart` + `lib/app/production_routes.dart`.
