# Supported platforms

## Officially supported (QA + store track)

| Platform | Status | Notes |
|----------|--------|-------|
| **Android** | Supported | Flavors `dev` / `stage` / `prod`; Play upload via AAB. See README Android quickstart and `docs/PUBLISH_READY_CHECKLIST.md`. |
| **iOS** | Supported | Bundle `com.carzo.app`; Codemagic + Sideloadly path in `docs/IOS_TESTING.md`. |

CI covers Flutter analyze/tests and (where configured) Android emulator integration smoke. Store gates target mobile only.

## Desktop (not supported)

The repo includes Flutter-generated **`macos/`**, **`windows/`**, and **`linux/`** runners. They are **scaffold only**:

- Not covered by CI
- Not part of publish / store checklists
- Not exercised in real-device QA docs
- Plugins used by the mobile app (maps, image picker, push, secure storage, etc.) may be missing, stubbed, or untested on desktop

**Do not** ship or advertise desktop builds until a dedicated desktop QA plan and CI job exist.

If you open the project in an IDE that offers “Windows desktop” / “macOS” / “Linux” run targets, treat failures there as expected for this product.

## Web

`flutter build web` may appear in older README notes. Web is **not** a supported product surface for launch.

## Related docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — entry points and CI
- [REAL_DEVICE_QA.md](REAL_DEVICE_QA.md) — mobile device QA
- [IOS_TESTING.md](IOS_TESTING.md) — iOS without a Mac
- [CONTRIBUTING.md](../CONTRIBUTING.md) — local setup (mobile-first)
