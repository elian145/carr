# Android App Links — Render setup

Production Android package: **`com.carnetiq.app`** (the `prod` flavor `applicationId`).
The backend serves `GET /.well-known/assetlinks.json` for this package
(`kk/routes/misc.py`), built from the `ANDROID_SHA256_CERT_FINGERPRINTS` env var.

## Required fingerprint set

`ANDROID_SHA256_CERT_FINGERPRINTS` on the Render **carr** service must be exactly
these two SHA-256 values, comma-separated, no spaces:

| Purpose | SHA-256 |
|---|---|
| Google Play App Signing certificate (required: this is what Play-installed builds are signed with) | `3A:5B:6A:0A:66:8E:EE:68:14:4B:BB:B3:E8:29:49:1F:3F:55:2B:0A:7A:AF:E0:75:C4:CC:3E:8C:E3:60:36:82` |
| Local/upload release keystore (directly installed, locally signed release builds) | `CD:C1:2F:74:DD:C0:E3:53:F1:61:14:D2:E3:66:CA:5A:71:34:E2:1F:49:23:89:95:4F:B1:39:45:8E:DB:52:9A` |

Exact dashboard value:

```
3A:5B:6A:0A:66:8E:EE:68:14:4B:BB:B3:E8:29:49:1F:3F:55:2B:0A:7A:AF:E0:75:C4:CC:3E:8C:E3:60:36:82,CD:C1:2F:74:DD:C0:E3:53:F1:61:14:D2:E3:66:CA:5A:71:34:E2:1F:49:23:89:95:4F:B1:39:45:8E:DB:52:9A
```

Notes:

- The Play App Signing value comes from Play Console → **Setup → App integrity →
  App signing key certificate**. It is not derivable from the local keystore.
- The upload value comes from `python scripts/print_android_app_link_sha.py`
  (keystore `release-keystore.jks`, alias `upload`).
- The earlier fingerprint `9E:7A:AC:CF:…:97:E8` (documented in July 2026 as an
  "upload keystore", before the current keystore existed) is stale: it is neither
  the Play signing key nor the current upload key. It must not be restored.

## Keep it configured

`ANDROID_SHA256_CERT_FINGERPRINTS` is **dashboard-managed** (`sync: false` in
`render.yaml`). The value is deliberately not stored in the repo, so a Render
Blueprint sync cannot overwrite it. (A previous literal `value:` in `render.yaml`
could silently revert the live fingerprints on sync.)

1. Render Dashboard → **carr** service → **Environment**
2. Set `ANDROID_SHA256_CERT_FINGERPRINTS` to the exact dashboard value above.
3. Save and redeploy (the route sends `Cache-Control: public, max-age=300`).
4. If Play App Signing is ever rotated, replace/append the new certificate SHA-256 here.

## Verify

```bash
curl https://carr-5hrm.onrender.com/.well-known/assetlinks.json
python scripts/print_android_app_link_sha.py --verify-host https://carr-5hrm.onrender.com
python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com --require-app-links
```

The JSON must show package `com.carnetiq.app` and both fingerprints above.

On a Play-installed device, confirm verification state:

```bash
adb shell pm get-app-links com.carnetiq.app
```

Known limitation (MT-05, 2026-09-18): Android's automatic verification previously
timed out for the Render default hostname (the trailing-dot form
`carr-5hrm.onrender.com.` returns a Render routing 404). If domain state does not
become `verified` even with the correct fingerprints, move public App Links to a
custom domain (`APP_LINK_HOST`, iOS associated domains, and `LISTING_SHARE_WEB_BASE`).

Android client: `android:autoVerify="true"` on the HTTPS `/listing` intent-filter in `AndroidManifest.xml`, host from `APP_LINK_HOST` (default `carr-5hrm.onrender.com`).
