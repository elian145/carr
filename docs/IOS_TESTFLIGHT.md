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

### B. Apple Developer Portal (code signing) — required

Codemagic → **Team settings** (not only the app) → **Integrations** → **Developer Portal**:

- Connect with the **same** Apple ID that owns your paid developer team.
- Role must be **Admin** or **App Manager** so profiles can be created.

### C. Register the bundle ID in Apple (if missing)

1. [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. **+** → **App IDs** → bundle ID **`com.carzo.app`** (exact spelling).
3. Enable **Push Notifications** (and **Associated Domains** if you use universal links).
4. Save.

### D. App in App Store Connect

App Store Connect → **Apps** → app with bundle ID **`com.carzo.app`** must exist (you created CARZO + SKU earlier).

## 5) Fix “No matching profiles found for com.carzo.app”

Often shows at **Initializing build** — Codemagic has no App Store profile yet.

### A. Add App Store Connect API key (required)

1. [Create API key](https://appstoreconnect.apple.com/access/integrations/api) (role **App Manager**).
2. Codemagic → **Teams** → **Team integrations** → **Developer Portal** → **Manage keys** → **Add key**
3. Issuer ID + Key ID + upload **.p8**
4. Name must match `codemagic.yaml`: `app_store_connect: App Store Connect` (or change yaml to your name)

### B. Create signing in Codemagic UI (do once) — fixes “without certificate private key”

**Team settings** → **codemagic.yaml settings** → **Code signing identities**

1. **iOS certificates** tab → **Generate certificate**
   - Type: **Apple Distribution**
   - Pick your **App Store Connect API key**
   - Reference name: e.g. `carzo_distribution`
   - **Download** the `.p12` if offered (backup only; Codemagic keeps the private key)
2. **iOS provisioning profiles** tab → **Fetch profiles**
   - Category: **App Store profiles**
   - Select **com.carzo.app**
   - Reference name: e.g. `carzo_appstore` → **Download selected**

> Do **not** only create a certificate on [developer.apple.com](https://developer.apple.com) — Codemagic cannot use it without the **private key**. Always **Generate** in Codemagic UI (or paste `CERTIFICATE_PRIVATE_KEY` below).

### B2. Optional: `CERTIFICATE_PRIVATE_KEY` env var (advanced)

Only if you prefer CLI `--create` on every build:

1. On a PC (once): `openssl genpkey -algorithm RSA -out ios_distribution_private_key.pem -pkeyopt rsa_keygen_bits:2048`
2. Codemagic → app → **Environment variables** → group `code-signing` → secret **`CERTIFICATE_PRIVATE_KEY`** = entire `.pem` file (including `BEGIN` / `END` lines)
3. Add group `code-signing` to the TestFlight workflow in Codemagic UI if not in yaml

Use the **same** key every time or Apple will create extra distribution certificates (max 3).

### C. Apple

- App ID **com.carzo.app** with **Push Notifications**
- App Store Connect app with same bundle ID

### D. Rebuild **iOS TestFlight (signed, push enabled)**

Log must pass: **Fetch App Store signing files** → **Add certificates to keychain** → **Apply code signing profiles**

- **Cannot save Signing Certificates without certificate private key** → do **section B** (Generate certificate in Codemagic UI), then rebuild
- **401 / invalid key** → fix API key in step A
- **Too many distribution certificates** → revoke old at [developer.apple.com](https://developer.apple.com/account/resources/certificates/list), generate again in Codemagic

## 6) Fix workflow integration name

Open `codemagic.yaml` → workflow **`ios-testflight`**.

Change:

```yaml
integrations:
  app_store_connect: Carzo ASC   # ← your exact integration name from step 4A
```

Commit and push if you change the name.

## 7) Run the TestFlight build

1. Codemagic → **Workflows** → **iOS TestFlight (signed, push enabled)**.
2. Branch **main** → **Start new build**.
3. Wait until green (first time may take ~15–25 min).
4. Build uploads to App Store Connect automatically (`submit_to_testflight: true`).

## 8) Install on iPhone

1. Install **TestFlight** from the App Store.
2. App Store Connect → your app → **TestFlight** → wait for build **Processing** → **Ready to test** (often 10–30 min after upload).
3. Add yourself as **Internal testing** tester (same Apple ID as developer team).
4. Open TestFlight on iPhone → install **CARZO**.

## 9) Test push

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
