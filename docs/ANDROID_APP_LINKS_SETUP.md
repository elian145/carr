# Android App Links — one-time Render setup

Your upload keystore SHA-256 (from `python scripts/print_android_app_link_sha.py`):

```
9E:7A:AC:CF:0B:CE:7E:A3:0E:B9:9D:AF:DF:37:8E:1D:3E:6C:F6:C5:E8:C8:22:41:1E:53:F5:A5:72:40:97:E8
```

## Steps

1. Render Dashboard → **carr** service → **Environment**
2. Add / update:
   - Key: `ANDROID_SHA256_CERT_FINGERPRINTS`
   - Value: the fingerprint above (comma-separate multiple SHAs, no spaces)
3. **Save** → wait for redeploy
4. Verify:
   ```bash
   python scripts/verify_production_host.py --host https://carr-5hrm.onrender.com --require-app-links
   ```
5. After first Play Console upload with Play App Signing, open **Setup → App integrity**, copy the **App signing** certificate SHA-256, append it to the same env var (comma-separated), redeploy again.

Until this env is set, `https://carr-5hrm.onrender.com/.well-known/assetlinks.json` returns **404 by design**.
