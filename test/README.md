# Flutter tests

| File | What it exercises |
|------|-------------------|
| `app_smoke_test.dart` | **Production** shell (`legacy.MyApp` — same as `main.dart`) |
| `widget_test.dart` | Production shell builds without crashing |
| `legacy_profile_widget_test.dart` | Profile page loads username via `ApiService.getProfile()` |
| `legacy_sell_step1_widget_test.dart` | Sell flow step 1 (`/sell` + `startFresh`) shows listing wizard UI |
| `legacy_chat_list_widget_test.dart` | Chat list loads rows from `/api/chats` via `ApiService.getChats()` |
| `legacy_car_detail_widget_test.dart` | Car detail from cache and from mock GET `/cars/:id` |
| `legacy_chat_conversation_widget_test.dart` | Chat conversation composer + empty history state |
| `legacy_my_listings_widget_test.dart` | My listings empty state via `/api/my_listings` compat |
| `legacy_favorites_widget_test.dart` | Favorites guest login prompt |
| `legacy_favorites_empty_widget_test.dart` | Authenticated favorites empty state from mock API |
| `legacy_login_widget_test.dart` | Login form fields and empty-credential validation |
| `api_chat_test.dart` | `getChats`, unread count, send message, message history against mock API |
| `api_profile_favorites_test.dart` | `getProfile`, `getFavorites`, `getMyListings`, `getCarDetail` against mock API |
| `api_integration_test.dart` | `createCar`, `toggleFavorite`, `createSavedSearch`, `updateCar`, `getCars` against mock API |
| `carzo_app_smoke_test.dart` | Migration shell (`CarzoApp` / `lib/app`) — not used in production |

All tests use `fake_api_server.dart`, which binds [ApiService.testHttpClient] to an in-memory [MockClient] (no loopback server or fixed ports).

```bash
flutter test
```

Backend smoke (separate from Flutter):

```bash
python scripts/smoke_tests/test_backend_factory_smoke.py
```
