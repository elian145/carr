# Flutter tests

| File | What it exercises |
|------|-------------------|
| `app_smoke_test.dart` | **Production** shell (`ProductionApp` — same as `main.dart`) |
| `widget_test.dart` | Production shell builds without crashing |

All tests use `fake_api_server.dart`, which binds an ephemeral port and sets a runtime `API_BASE` override (no fixed port collisions in parallel runs).

```bash
flutter test
```

Backend smoke (separate from Flutter):

```bash
python scripts/smoke_tests/test_backend_factory_smoke.py
```
