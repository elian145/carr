# Flutter tests

| File | What it exercises |
|------|-------------------|
| `app_smoke_test.dart` | **Production** shell (`legacy.MyApp` — same as `main.dart`) |
| `widget_test.dart` | Production shell builds without crashing |
| `legacy_profile_widget_test.dart` | Profile page loads username via `ApiService.getProfile()` |
| `api_profile_favorites_test.dart` | `getProfile`, `getFavorites`, `getMyListings`, `getCarDetail` against mock API |
| `carzo_app_smoke_test.dart` | Migration shell (`CarzoApp` / `lib/app`) — not used in production |

All tests use `fake_api_server.dart`, which binds [ApiService.testHttpClient] to an in-memory [MockClient] (no loopback server or fixed ports).

```bash
flutter test
```

Backend smoke (separate from Flutter):

```bash
python scripts/smoke_tests/test_backend_factory_smoke.py
```
