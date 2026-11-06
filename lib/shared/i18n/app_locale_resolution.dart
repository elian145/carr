import 'package:flutter/widgets.dart';

/// F-09: single source of truth for how the production app maps an explicit
/// in-app selection or a device locale onto one of the locales it ships
/// (`en`, `ar`, `ku`).
///
/// Sorani Kurdish is `ckb` in CLDR/BCP-47 (and what Android/iOS usually report
/// on a device set to Kurdish (Sorani), possibly with a region or script such
/// as `ckb_IQ`, `ckb-IR`, `ckb_Arab_IQ`), but this app ships it as `ku` (see
/// `lib/l10n/app_ku.arb`, `LocaleController.supportedCodes`, and the backend's
/// `SUPPORTED_LOCALES`). `ckb` must therefore never be added as a fourth
/// supported locale; it is canonicalised to `ku` before matching.

/// Locales the production `MaterialApp` advertises.
const List<Locale> kAppSupportedLocales = <Locale>[
  Locale('en'),
  Locale('ar'),
  Locale('ku'),
];

/// Language code the app uses for Sorani Kurdish.
const String kKurdishLanguageCode = 'ku';

/// Maps the Sorani language code `ckb` (any case) to the app's `ku`; every
/// other code (including `en`/`ar`/`ku` and unknown codes) is returned as-is.
String? canonicalAppLanguageCode(String? languageCode) {
  if (languageCode == null) return null;
  return languageCode.toLowerCase() == 'ckb' ? kKurdishLanguageCode : languageCode;
}

/// Maps a `ckb` locale (with any country/script, e.g. `ckb_IQ`,
/// `ckb_Arab_IQ`) to the plain `ku` locale; any other locale is returned
/// unchanged (so `en`/`ar` behave exactly as before).
Locale? canonicalAppLocale(Locale? locale) {
  if (locale == null) return null;
  if (locale.languageCode.toLowerCase() != 'ckb') return locale;
  return const Locale(kKurdishLanguageCode);
}

/// `localeResolutionCallback` body for the production app.
///
/// * An explicit in-app selection wins (a legacy persisted `ckb` is read as
///   `ku`).
/// * Otherwise the device locale is matched on language code against
///   [supported], with `ckb*` treated as `ku`.
/// * Anything else (including a null device locale) falls back to `en`.
Locale resolveAppLocale({
  required Locale? explicit,
  required Locale? device,
  required Iterable<Locale> supported,
}) {
  final chosen = canonicalAppLocale(explicit);
  if (chosen != null) return chosen;
  final deviceCode = canonicalAppLanguageCode(device?.languageCode);
  if (deviceCode == null) return const Locale('en');
  for (final candidate in supported) {
    if (candidate.languageCode == deviceCode) return candidate;
  }
  return const Locale('en');
}
