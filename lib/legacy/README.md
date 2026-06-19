# Legacy URL aliases

All `/legacy_*` routes are registered in `lib/app/production_routes.dart` as aliases to the same builders as production paths. They exist for old bookmarks, deep links, and smoke tests.

| Legacy URL | Canonical route |
|------------|-----------------|
| `/legacy_home` | `/` |
| `/legacy_home_filters` | `/home_filters` |
| `/legacy_sell` | `/sell` |
| `/legacy_car_detail` | `/car_detail` |
| `/legacy_comparison` | `/comparison` |
| `/legacy_favorites` | `/favorites` |
| `/legacy_profile` | `/profile` |
| `/legacy_settings` | `/settings` |
| `/legacy_login` | `/login` |
| `/legacy_saved_searches` | `/saved-searches` |

The former `main_legacy.dart` monolith and part files were removed; production UI lives under `lib/pages/` and `lib/app/`.
