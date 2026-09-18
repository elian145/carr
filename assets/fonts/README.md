# Bundled fonts

- **Orbitron** (variable) — OFL, from [google/fonts](https://github.com/google/fonts/tree/main/ofl/orbitron)
- **Barlow Condensed Black** — OFL, from [google/fonts](https://github.com/google/fonts/tree/main/ofl/barlowcondensed)
- **Noto Sans Arabic** (`NotoSansArabic-Regular.ttf`, variable, `wght` 100–900) — **SIL Open Font License 1.1**, from the official source [google/fonts `ofl/notosansarabic`](https://github.com/google/fonts/tree/main/ofl/notosansarabic) (upstream: [notofonts/arabic](https://github.com/notofonts/arabic)). The unmodified license text as published at that source is included alongside the font as `NotoSansArabic-OFL.txt`. Covers Arabic script including the extended Sorani Kurdish letters the app uses (`ڕ ڵ ھ ێ ۆ` and others). Used for `ar`/`ku` text via `AppFonts` instead of the Latin-only Orbitron/Barlow Condensed fonts above (see U-04 in `PRODUCTION_AUDIT.md`); English keeps the branded Latin fonts.

Bundled so the app does not fetch fonts at runtime.
