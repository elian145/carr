# Store listing assets

Create these before Play Console / App Store Connect submission. Not bundled in the app.

## Required

| Asset | Android | iOS |
|-------|---------|-----|
| App icon | 512×512 PNG (Play) | 1024×1024 PNG (App Store) — source: `assets/icon/app_icon.png` |
| Phone screenshots | 2–8 images, min 320px short side | 6.7" and 5.5" sizes per App Store Connect |
| Feature graphic | 1024×500 PNG | N/A |

## Recommended

- Tablet screenshots (7" and 10" for Play)
- Short description (80 chars) and full description
- Privacy policy URL: `{API_BASE}/privacy`
- Terms URL: `{API_BASE}/terms`
- Support email from `/api/config/trust`

See `docs/STORE_SUBMISSION.md` for Data Safety and App Privacy form answers.
