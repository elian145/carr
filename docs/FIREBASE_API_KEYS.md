# Firebase and Google API key restrictions

Committed config files contain API keys that are extractable from APK/IPA builds. Restrict them in Google Cloud Console before store upload.

## Firebase (Android + iOS)

| File | Package / bundle |
|------|------------------|
| `android/app/src/prod/google-services.json` | `com.carnetiq.app` (prod flavor; file also lists the legacy `com.carzo.app*` clients) |
| `ios/Runner/GoogleService-Info.plist` | `com.carzo.app` |

**Actions:**
1. Create a **separate Firebase project** for dev/stage (`com.carzo.app.dev`, `com.carzo.app.stage`) — do not share prod FCM/analytics with dev builds.
   **Status (F-20): NOT DONE.** `dev`/`stage` still contain the production project `carzo-prod`; only the owner can create the new projects. `python scripts/verify_firebase_isolation.py` warns in CI until fixed (it also errors if a flavor's file has no client for its applicationId, and flags a dev/stage file that reuses the prod project number, package, app id or API key; `ios/Runner/GoogleService-Info.plist` is a single prod-project file with no dev/stage variant and is not covered by the script); after replacing the files, switch the CI step to `--strict`.
2. Replace `android/app/src/dev/google-services.json` and `android/app/src/stage/google-services.json` with configs from the dev Firebase project.
3. In Firebase Console → Project settings → restrict API keys to your Android package + release SHA-1 and iOS bundle ID.

## Google Maps / Places

| Platform | Injection |
|----------|-----------|
| Android | `GOOGLE_MAPS_API_KEY` in `android/local.properties` or CI |
| iOS | `IOS_GOOGLE_MAPS_API_KEY`, `IOS_GOOGLE_PLACES_API_KEY` at build time |

Restrict each key to:
- Application restriction: Android apps (`com.carzo.app` + SHA-1) or iOS apps (`com.carzo.app`)
- API restriction: Maps SDK for Android/iOS, Places API only

## Verify after Play upload

```bash
python scripts/print_android_app_link_sha.py
# Set output on Render as ANDROID_SHA256_CERT_FINGERPRINTS
python scripts/verify_production_host.py --host https://your-host --require-app-links
```
