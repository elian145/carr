# Integration tests (device)

`integration_test/app_smoke_test.dart` requires a connected Android/iOS device or emulator:

```bash
flutter test integration_test
```

CI runs the broader headless smoke suite via `test/app_smoke_test.dart` inside `flutter test`.
