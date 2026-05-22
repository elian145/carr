# iPhone push via TestFlight (paid Apple Developer, no Mac)

Use this instead of **Sideloadly** when you need **push notifications**. Sideloadly cannot use your paid push certificates properly.

## What you need

- **Paid Apple Developer** account (you have this)
- **Codemagic** account connected to this repo
- **Firebase** project `carzo-prod` with **APNs .p8 key** uploaded (Cloud Messaging → `com.carzo.app`)
- **Render** backend running (`https://carr-5hrm.onrender.com`)
- iPhone with **TestFlight** app installed (free from App Store)

## 1) Apple Developer Portal (browser)

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **com.carzo.app** (create if missing).
2. Enable capability **Push Notifications** → Save.
3. Note your **Team ID** (10 characters, e.g. `LN3R46L4H8`) — must match `ios/ExportOptions.plist`.

## 2) Firebase (browser)

1. [Firebase Console](https://console.firebase.google.com) → project **carzo-prod**.
2. **Project settings** → **Cloud Messaging** → Apple app **com.carzo.app**.
3. Upload **APNs Authentication Key** (.p8) + Key ID + Team ID.

## 3) App Store Connect (browser)

1. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → new app **CARZO**, bundle ID **com.carzo.app**.
2. You do not need a store listing finished to use TestFlight.

## 4) Codemagic integrations (one-time)

### A. App Store Connect API key

1. [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) → **+** generate key.
2. Role: **App Manager** (or Admin).
3. Download `.p8`, note **Issuer ID** and **Key ID**.

In **Codemagic** → your app → **Teams** (or account) → **Integrations** → **App Store Connect**:

- Add the API key (Issuer ID, Key ID, upload `.p8`).
- Remember the **integration name** (e.g. `Carzo ASC`).

### B. Apple Developer Portal (code signing)

Codemagic → **Integrations** → **Developer Portal**:

- Connect with Apple ID that has access to your team.
- Codemagic will create/fetch distribution certs and profiles for **com.carzo.app**.

## 5) Fix workflow integration name

Open `codemagic.yaml` → workflow **`ios-testflight`**.

Change:

```yaml
integrations:
  app_store_connect: Carzo ASC   # ← your exact integration name from step 4A
```

Commit and push if you change the name.

## 6) Run the TestFlight build

1. Codemagic → **Workflows** → **iOS TestFlight (signed, push enabled)**.
2. Branch **main** → **Start new build**.
3. Wait until green (first time may take ~15–25 min).
4. Build uploads to App Store Connect automatically (`submit_to_testflight: true`).

## 7) Install on iPhone

1. Install **TestFlight** from the App Store.
2. App Store Connect → your app → **TestFlight** → wait for build **Processing** → **Ready to test** (often 10–30 min after upload).
3. Add yourself as **Internal testing** tester (same Apple ID as developer team).
4. Open TestFlight on iPhone → install **CARZO**.

## 8) Test push

1. Open CARZO (TestFlight build, **not** Sideloadly) → log in → allow **notifications**.
2. Log out and log in once (registers FCM token on server).
3. On a **second** account/device, send a chat message.
4. On the receiver iPhone: app **in background** or **closed** → you should see a **banner**.

If no banner: Render logs for `firebase_token` / `FCM send failed`; confirm APNs key in Firebase.

## Sideloadly vs TestFlight

| | Sideloadly | TestFlight |
|---|------------|------------|
| Needs Mac | No | No (Codemagic builds) |
| Push notifications | No | Yes (with steps above) |
| Expires | 7 days (free Apple ID sign) / varies | TestFlight build validity |

Keep Sideloadly for quick UI tests; use **TestFlight** for push and pre-release QA.
