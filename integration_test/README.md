# Integration tests (device / emulator)

`integration_test/app_smoke_test.dart` boots the production `MyApp` shell with
an in-memory API stub (`test/fake_api_server.dart`). It must run on a real
Android device or emulator (product flavor required):

```bash
# Local (device/emulator connected)
bash scripts/flutter_integration_ci.sh
# or:
flutter test integration_test/app_smoke_test.dart --flavor dev
```

## CI

**GitHub Actions** (`Flutter CI` → job `Integration smoke (Android emulator)`)
boots an AVD via `reactivecircus/android-emulator-runner` and runs
`scripts/flutter_integration_ci.sh` on every push/PR to `main`.

Headless widget smoke (no device) remains in `test/app_smoke_test.dart` via
`scripts/flutter_test_ci.sh`.
