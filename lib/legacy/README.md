# Legacy route aliases

Production entry: `lib/main.dart` → [ProductionApp] (`lib/app/production_app.dart`).

All `/legacy_*` URLs are **aliases** to the same modern screens as production. They exist for rollback URLs and smoke tests only.

Defined in `lib/legacy/legacy_fallback_routes.dart` (`buildLegacyFallbackRoutes()`), merged in [ProductionApp].

| Route | Screen |
|-------|--------|
| `/legacy_home` | `HomePage` |
| `/legacy_home_filters` | `HomeFiltersPage` |
| `/legacy_sell` | Modern `SellPage` + draft gate |
| `/legacy_car_detail` | `CarDetailPage` |
| `/legacy_favorites` | `FavoritesPage` |
| `/legacy_profile` | `ProfilePage` |
| `/legacy_settings` | `SettingsPage` |
| `/legacy_login` | `LoginPage` |
| `/legacy_comparison` | `ComparisonPage` |
| `/legacy_saved_searches` | `SavedSearchesPage` |

The former `main_legacy.dart` monolith and part files (`home_page_legacy.dart`, `sell_flow_legacy.dart`, etc.) were removed after all routes and production UI moved to `lib/pages/` and `lib/app/`.

## Tooling (historical)

- `tools/split_legacy_part.py` — extract a line range into a part file (legacy migration)
- `tools/restore_legacy_parts_from_git.py` — recover parts from git if needed
