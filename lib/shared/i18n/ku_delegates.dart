import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Fallback delegates to provide Material/Cupertino/Widgets localizations
/// for the app's Kurdish (`ku`) locale.
///
/// U-07: flutter_localizations ships no official Kurdish (`ku`/`ckb`)
/// translation, so genuine Kurdish system chrome (date-picker strings,
/// "OK"/"Cancel", etc.) is not available from the framework. This file
/// previously proxied Kurdish Material/Cupertino strings to Arabic, which
/// silently rendered a linguistically WRONG language to Kurdish users --
/// Arabic and Kurdish are unrelated languages, so this was not a "close
/// enough" approximation, and it misrepresented the app as having real
/// Kurdish system-chrome support.
///
/// We now fall back to English for that system chrome instead of Arabic:
/// English is the app's base locale, is guaranteed to be a complete and
/// grammatically correct translation (unlike inventing a partial Kurdish
/// one here, which is out of scope for this fix), and does not pretend to
/// be Kurdish. This is a deliberate, documented choice (see
/// PRODUCTION_AUDIT.md U-07), not a silent/accidental fallback.
///
/// The app-wide RTL reading direction for Kurdish is preserved
/// independently of this choice: this app's `ku` locale content (see
/// `lib/l10n/app_ku.arb`) is written in Sorani/Central Kurdish using the
/// Arabic script, which is RTL. [KuWidgetsLocalizationsDelegate] supplies
/// that `textDirection` directly (not proxied from Arabic) alongside
/// English copy for its handful of accessibility-label strings, so Kurdish
/// layout stays RTL even though the Material/Cupertino delegates below now
/// source their strings from English rather than Arabic.
class KuMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KuMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<MaterialLocalizations> old,
  ) => false;
}

class KuCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const KuCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    return GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<CupertinoLocalizations> old,
  ) => false;
}

class KuWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const KuWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    // Kurdish (Sorani/Arabic-script, as used by this app's `ku` locale) is
    // RTL, but flutter_localizations has no `ku`/`ckb` entry to source that
    // from. Provide RTL directly (no Arabic text or proxying involved)
    // plus the English copy for WidgetsLocalizations' small set of
    // accessibility-label strings (drag-reorder semantics, copy/cut/paste).
    return SynchronousFuture<WidgetsLocalizations>(
      const _KuWidgetsLocalizations(),
    );
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<WidgetsLocalizations> old,
  ) => false;
}

/// English `WidgetsLocalizations` copy with the [textDirection] overridden
/// to RTL for Kurdish (see class doc above and U-07 in PRODUCTION_AUDIT.md).
class _KuWidgetsLocalizations extends WidgetsLocalizationEn {
  const _KuWidgetsLocalizations();

  @override
  TextDirection get textDirection => TextDirection.rtl;
}
