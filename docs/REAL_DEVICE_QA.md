# CARZO Real-Device QA Runbook

Run this checklist on a production-like Android build and an iOS TestFlight/App Store build before store submission.

## Current Device Availability

- Android emulator detected locally: `emulator-5554`.
- No iOS device can be tested from this Windows machine. iOS QA must be run from a Mac with Xcode/TestFlight or a physical iPhone using the TestFlight build.

## Required Build Inputs

- Android: production AAB or APK built with `--flavor prod` and `API_BASE=https://carr-5hrm.onrender.com`.
- iOS: App Store/TestFlight build with `API_BASE=https://carr-5hrm.onrender.com`.
- Backend: Render production service with `DATABASE_URL`, email provider, upload storage, `APPLE_TEAM_ID`, and `ANDROID_SHA256_CERT_FINGERPRINTS`.
- Firebase: Android `android/app/src/prod/google-services.json` and iOS `GoogleService-Info.plist`.

## Smoke Flow

1. Fresh install the app.
2. Launch app and verify no crash before login.
3. Sign up with a new account.
4. Log out and log back in.
5. Trigger password reset with a real email and confirm the email/code flow works.
6. Create a listing with required vehicle fields.
7. Add listing photos.
8. Add a listing video and confirm playback.
9. Edit the listing.
10. Mark listing sold and active again if the account has access.
11. Delete or deactivate a test listing if needed.

## Media And Storage

1. Upload photos, close app, reopen app, and confirm photos still load.
2. Restart/redeploy backend, then confirm previously uploaded media still loads.
3. Confirm image/video URLs are not local temporary paths.

## Maps And Dealer Flow

1. Open dealer location picker.
2. Search/select a place.
3. Confirm map tiles load.
4. Save dealer location/profile.
5. Reopen profile and verify saved fields.

## Network (do this before push testing)

1. On the device, open Safari and load `https://carr-5hrm.onrender.com/health` — it must load (not “server not found”).
2. If the app shows a socket/DNS error, fix Wi‑Fi or cellular data first; push and chat cannot work offline.

## Chat And Push

1. Use two accounts.
2. Send a chat message from account A to account B.
3. Confirm unread count updates.
4. Put app in background and confirm push notification arrives.
5. Tap push notification and confirm it opens the expected conversation/listing.

## Deep Links

Automated check (from a PC):

```bash
python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com --require-app-links
```

Manual on device:

1. Open `https://carr-5hrm.onrender.com/.well-known/apple-app-site-association`; it must return JSON.
2. Open `https://carr-5hrm.onrender.com/.well-known/assetlinks.json`; it must return JSON, not 404 (requires `ANDROID_SHA256_CERT_FINGERPRINTS` on Render).
3. Send `https://carr-5hrm.onrender.com/listing/<valid-listing-id>` to the device.
4. Tap the link from Messages/email/browser and confirm it opens the app listing.
5. Test `carzo://listing?id=<valid-listing-id>` for fallback behavior.

## Network And Error Handling

1. Disable network and open the app.
2. Confirm errors are readable and app does not crash.
3. Re-enable network and confirm recovery without reinstalling.
4. Test slow network while uploading media.

## Store Submission Blockers

- Do not submit until Android App Links return 200 for `assetlinks.json`.
- Do not submit until Android Firebase prod config is present and targets `com.carzo.app`.
- Do not submit until privacy policy and support URLs are live.
- Do not submit until at least one physical Android device and one physical iPhone/TestFlight run pass this checklist.
