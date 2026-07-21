# Store listing assets

Create these before Play Console / App Store Connect submission. Not bundled in the app.

## Ready in this folder

| File | Use |
|------|-----|
| `play_icon_512.png` | Google Play high-res icon (512×512) |
| `app_store_icon_1024.png` | App Store icon (1024×1024) |
| `play_feature_graphic.png` | Google Play feature graphic (1024×500) |
| `listing_copy.md` | Short/full description drafts |
| `screenshots/{en,ar,ku}/phone_6_7/*.png` | Phone screenshots 1290×2796 (6.7") |
| `screenshots/{en,ar,ku}/phone_5_5/*.png` | Phone screenshots 1242×2208 (5.5") |

## Phone screenshot set

Each locale (`en`, `ar`, `ku`) has five screens at both sizes:

1. `01_home` — home feed  
2. `02_listing_detail` — listing detail  
3. `03_dealers` — dealerships directory  
4. `04_sell` — add listing (sell)  
5. `05_profile` — profile  

Recapture (emulator + `com.carzo.app.dev` installed, Pillow required):

```bash
python scripts/capture_store_screenshots.py
# or: python scripts/capture_store_screenshots.py --locales en
```

Raw dumps under `screenshots/_raw/` are gitignored.

Tablet screenshots remain optional (7" / 10").

## URLs for store forms

- Privacy: `https://carr-5hrm.onrender.com/privacy`
- Terms: `https://carr-5hrm.onrender.com/terms`
- Support: from `/api/config/trust` (`SUPPORT_EMAIL`)

See `docs/STORE_SUBMISSION.md` for Data Safety and App Privacy form answers.
