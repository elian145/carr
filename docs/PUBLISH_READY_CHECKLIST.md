# CARZO Publish-Ready Checklist

This checklist is the final gate before uploading Android AAB/APK or iOS builds.

## 1) Required identifiers

- Android `applicationId` and `namespace` are `com.carzo.app` (prod flavor).
- iOS bundle identifier is `com.carzo.app`.
- No `com.example.*` identifier remains in production files.

## 2) Required secrets/configuration

- `android/signing.properties` exists for release builds.
- Android Firebase files exist for all flavors:
  - `android/app/src/dev/google-services.json`
  - `android/app/src/stage/google-services.json`
  - `android/app/src/prod/google-services.json`
- iOS Firebase config exists:
  - `ios/Runner/GoogleService-Info.plist`
- iOS map keys are provided at build time:
  - `IOS_GOOGLE_MAPS_API_KEY`
  - `IOS_GOOGLE_PLACES_API_KEY`
- Android map key is provided in `android/local.properties` as `GOOGLE_MAPS_API_KEY` or injected by CI.

## 3) Network and runtime safety

- Release builds use HTTPS `API_BASE` only.
- `flutter build ... --dart-define=API_BASE=https://your-api-domain` is used for production artifacts.
- No local IP or localhost release builds are uploaded.

## 4) QA and validation commands

- `flutter clean`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Android release builds:
  - `flutter build apk --release --flavor prod --dart-define=API_BASE=https://your-api-domain`
  - `flutter build appbundle --release --flavor prod --dart-define=API_BASE=https://your-api-domain`
- iOS release/TestFlight build uses release plist and production API base.

## 5) Store compliance

- Privacy Policy URL and Terms URL are ready.
- Data safety / privacy nutrition labels are completed based on actual app behavior.
- Support email/contact is available in store listing.
- App screenshots, icon, and release notes are finalized.
