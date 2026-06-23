# App icon

- **`app_icon.png`** — source image for `flutter_launcher_icons` (replace with a **1024×1024** PNG before final store submission).
- Regenerate platform icons and splash:

```bash
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Current file is seeded from `backend/logo.png` for development builds.
