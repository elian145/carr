# Flutter tests

| File | What it exercises |
|------|-------------------|
| `app_smoke_test.dart` | **Production** shell (`legacy.MyApp` — same as `main.dart`) |
| `widget_test.dart` | Production shell builds without crashing |
| `legacy_profile_widget_test.dart` | Profile page loads username via `ApiService.getProfile()` |
| `legacy_sell_step1_widget_test.dart` | Sell flow step 1 (`/sell` + `startFresh`) shows listing wizard UI |
| `legacy_sell_steps_widget_test.dart` | Sell flow steps 2–5 via draft snapshot resume |
| `legacy_chat_list_widget_test.dart` | Chat list loads rows from `/api/chats` via `ApiService.getChats()` |
| `legacy_car_detail_widget_test.dart` | Car detail from cache and from mock GET `/cars/:id` |
| `legacy_chat_conversation_widget_test.dart` | Chat conversation composer + empty history state |
| `legacy_chat_send_widget_test.dart` | Chat conversation sends text through mock `/chat/:id/send` |
| `legacy_my_listings_widget_test.dart` | My listings empty state via `/api/my_listings` compat |
| `legacy_favorites_widget_test.dart` | Favorites guest login prompt |
| `legacy_favorites_empty_widget_test.dart` | Authenticated favorites empty state from mock API |
| `legacy_login_widget_test.dart` | Login form fields and empty-credential validation |
| `legacy_signup_widget_test.dart` | Signup form fields and terms gate on create account |
| `legacy_recently_viewed_guest_widget_test.dart` | Recently viewed guest AuthGuard redirect to login |
| `legacy_recently_viewed_empty_widget_test.dart` | Authenticated recently viewed route smoke |
| `legacy_analytics_empty_widget_test.dart` | Analytics empty seller state from mock `/analytics/listings` |
| `legacy_settings_widget_test.dart` | Settings page theme controls |
| `legacy_comparison_empty_widget_test.dart` | Comparison empty state |
| `legacy_dealers_directory_widget_test.dart` | Dealers directory empty search state |
| `legacy_edit_profile_widget_test.dart` | Edit profile loads session user fields |
| `legacy_forgot_password_widget_test.dart` | Forgot password recovery UI and empty-email validation |
| `legacy_reset_password_widget_test.dart` | Reset password prefills token from route args |
| `api_chat_test.dart` | `getChats`, unread count, send message, message history against mock API |
| `api_analytics_test.dart` | `AnalyticsService.getUserListingsAnalytics` and `trackView` against mock API |
| `api_auth_recovery_test.dart` | `forgotPassword` and `resetPassword` against mock API |
| `api_profile_favorites_test.dart` | `getProfile`, `getFavorites`, `getMyListings`, `getCarDetail` against mock API |
| `api_integration_test.dart` | `createCar`, `toggleFavorite`, `createSavedSearch`, `updateCar`, `getCars`, `getRecentlyViewed` against mock API |
| `carzo_app_smoke_test.dart` | Migration shell (`CarzoApp` / `lib/app`) — not used in production |

All tests use `fake_api_server.dart`, which binds [ApiService.testHttpClient] to an in-memory [MockClient] (no loopback server or fixed ports).

```bash
flutter test
```

Backend smoke (separate from Flutter):

```bash
python scripts/smoke_tests/test_backend_factory_smoke.py
```
