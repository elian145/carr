# CARZO Publish-Ready Checklist

This checklist is the final gate before uploading Android AAB/APK or iOS builds.

## 1) Required identifiers

- Android `applicationId` and `namespace` are `com.carzo.app` (prod flavor).
- iOS bundle identifier is `com.carzo.app`.
- No `com.example.*` identifier remains in production files.

## 2) Required secrets/configuration

- `android/signing.properties` exists for release builds.
- Android Firebase config exists for the production package:
  - `android/app/src/prod/google-services.json` with `package_name: com.carzo.app`
- iOS Firebase config exists:
  - `ios/Runner/GoogleService-Info.plist`
- iOS map keys are provided at build time:
  - `IOS_GOOGLE_MAPS_API_KEY`
  - `IOS_GOOGLE_PLACES_API_KEY`
- Android map key is provided in `android/local.properties` as `GOOGLE_MAPS_API_KEY` or injected by CI.
- Render/backend environment contains `ANDROID_SHA256_CERT_FINGERPRINTS`, so `/.well-known/assetlinks.json` returns 200.
- Render/backend environment contains `APPLE_TEAM_ID`, so `/.well-known/apple-app-site-association` returns 200.

## 3) Network and runtime safety

- Release builds use HTTPS `API_BASE` only.
- `flutter build ... --dart-define=API_BASE=https://your-api-domain` is used for production artifacts.
- No local IP or localhost release builds are uploaded.

## 4) Production backend (Render)

- See [`DEPLOY_ENV_CHECKLIST.md`](DEPLOY_ENV_CHECKLIST.md) for required env vars (Postgres, R2 or persistent disk, app links).

## 5) QA and validation commands

- `python scripts/verify_publish_ready.py` (static file/bundle-id checks; runs in CI)
- `flutter clean`
- `flutter pub get`
- `flutter analyze`
- `flutter test` (boots production `legacy.MyApp` with an ephemeral local API stub)
- Android release builds:
  - `flutter build apk --release --flavor prod --dart-define=API_BASE=https://your-api-domain`
  - `flutter build appbundle --release --flavor prod --dart-define=API_BASE=https://your-api-domain`
- iOS release/TestFlight build uses release plist and production API base.

## 6) Store compliance

- Root `LICENSE` (MIT) is present and matches README.
- Privacy Policy URL and Terms URL are ready.
- Data safety / privacy nutrition labels are completed based on actual app behavior.
- Support email/contact is available in store listing.
- Launcher icons generated: `dart run flutter_launcher_icons` (source: `assets/icon/app_icon.png`).
- App screenshots, icon, and release notes are finalized.
- See `docs/STORE_SUBMISSION.md` for permission justifications and data safety/privacy label inputs.
