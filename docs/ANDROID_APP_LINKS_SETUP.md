# Android App Links — Render setup

Verified against production (`https://carr-5hrm.onrender.com`) on 2026-07-21:

- `GET /.well-known/assetlinks.json` → **200**
- Package: `com.carzo.app`
- Upload keystore SHA-256 present on the host
- `/health` reports `app_links_android: true`

Your upload keystore SHA-256 (from `python scripts/print_android_app_link_sha.py`):

```
9E:7A:AC:CF:0B:CE:7E:A3:0E:B9:9D:AF:DF:37:8E:1D:3E:6C:F6:C5:E8:C8:22:41:1E:53:F5:A5:72:40:97:E8
```

## Keep it configured

1. Render Dashboard → **carr** service → **Environment**
2. Ensure:
   - Key: `ANDROID_SHA256_CERT_FINGERPRINTS`
   - Value: the fingerprint above (comma-separate multiple SHAs)
3. After first Play Console upload with Play App Signing, open **Setup → App integrity**, copy the **App signing** certificate SHA-256, append it to the same env var (comma-separated), redeploy again.

## Verify

```bash
python scripts/print_android_app_link_sha.py --verify-host https://carr-5hrm.onrender.com
python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com --require-app-links
```

Android client: `android:autoVerify="true"` on the HTTPS `/listing` intent-filter in `AndroidManifest.xml`, host from `APP_LINK_HOST` (default `carr-5hrm.onrender.com`).
