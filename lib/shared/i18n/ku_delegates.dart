import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Delegates that provide Material/Cupertino/Widgets localizations for the
/// app's Kurdish (`ku`) locale.
///
/// U-07: flutter_localizations ships no official Kurdish (`ku`/`ckb`)
/// translation, so the framework itself cannot supply genuine Kurdish
/// system chrome (date-picker strings, "OK"/"Cancel", text-selection
/// toolbar, etc.). This file previously proxied those strings to Arabic
/// (linguistically wrong -- Arabic and Kurdish are unrelated languages),
/// then to English (not wrong, but not Kurdish either -- see git history /
/// PRODUCTION_AUDIT.md U-07 for that intermediate state).
///
/// [_MaterialLocalizationKu] / [_CupertinoLocalizationKu] /
/// [_KuWidgetsLocalizations] now provide genuine Sorani Kurdish text for the
/// framework strings this app's flows actually surface to users (dialog
/// buttons, back/next/previous navigation, search, the text-selection
/// toolbar, date/time pickers, pull-to-refresh, expand/collapse hints,
/// etc.), by extending the generated *English* translation classes
/// (`MaterialLocalizationEn` / `CupertinoLocalizationEn` /
/// `WidgetsLocalizationEn`) and overriding only the visible-string getters
/// -- exactly the pattern flutter_localizations itself uses for English
/// locale variants (e.g. `MaterialLocalizationEnGb extends
/// MaterialLocalizationEn`). This keeps all non-overridden behavior
/// (parsing, `formatMediumDate`, `formatDecimal`, etc.) working exactly as
/// it already does.
///
/// Wording was sourced from/kept consistent with the terms this app's own
/// ARB file (`lib/l10n/app_ku.arb`) already uses for the same concepts
/// (e.g. "باشە" for OK, "هەڵوەشاندنەوە" for Cancel, "سڕینەوە" for Delete,
/// "کاتژمێر"/"خولەک" for Hour/Minute) -- see the per-getter comments below
/// for anything invented specifically for this file.
///
/// Deliberately NOT translated (left inherited from English), documented
/// per PRODUCTION_AUDIT.md U-07 rather than silently defaulted:
/// - Anything tied to date/number *formatting* rather than display text
///   (`dateSeparator`, `dateHelpText`'s `mm/dd/yyyy` pattern,
///   `datePickerDateOrderString`, AM/PM abbreviations, `dateRange*Raw`
///   semantic-label templates) -- these are coupled to the `intl`
///   `DateFormat`/`NumberFormat` objects below, which reuse English's
///   formatting (no Kurdish CLDR data exists in `intl`) so translating the
///   surrounding label text without changing the actual format would be
///   misleading.
/// - Hardware-keyboard key names (`keyboardKey*`, ~40 getters) and
///   `MenuBar`/`TabBar`/`PaginatedDataTable`/`AboutDialog`/
///   `UserAccountsDrawerHeader`/`ReorderableListView` strings -- this app
///   does not use any of those widgets (verified via repo-wide search), so
///   there is no reachable flow where a user would see them.
///
/// The app-wide RTL reading direction for Kurdish is preserved
/// independently of this file's string content: this app's `ku` locale
/// content (see `lib/l10n/app_ku.arb`) is written in Sorani/Central Kurdish
/// using the Arabic script, which is RTL.
/// [KuWidgetsLocalizationsDelegate]/[_KuWidgetsLocalizations] supplies that
/// `textDirection` directly (not proxied from Arabic or English).
class KuMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KuMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    // `intl` has no Kurdish (`ku`) CLDR date/number formatting data, so we
    // deliberately build these DateFormat/NumberFormat objects from the
    // English locale -- the same formatting this app already rendered
    // before this fix (Kurdish system chrome previously proxied to
    // English/Arabic wholesale). Only the *text* getters overridden on
    // [_MaterialLocalizationKu] below are genuinely Kurdish; formatting
    // behavior (digit grouping, month/day ordering, etc.) is unchanged.
    //
    // Loading the stock English delegate first is what actually
    // initializes `intl`'s date-formatting locale data as a side effect
    // (mirrors flutter_localizations' own internal
    // `loadDateIntlDataIfNotLoaded()`, which isn't exported for reuse
    // here); without it, constructing `intl.DateFormat.y('en')` etc.
    // directly throws `LocaleDataException`.
    await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
    return _MaterialLocalizationKu(
      fullYearFormat: intl.DateFormat.y('en'),
      compactDateFormat: intl.DateFormat.yMd('en'),
      shortDateFormat: intl.DateFormat.yMMMd('en'),
      mediumDateFormat: intl.DateFormat.MMMEd('en'),
      longDateFormat: intl.DateFormat.yMMMMEEEEd('en'),
      yearMonthFormat: intl.DateFormat.yMMMM('en'),
      shortMonthDayFormat: intl.DateFormat.MMMd('en'),
      decimalFormat: intl.NumberFormat.decimalPattern('en'),
      twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'en'),
    );
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
  Future<CupertinoLocalizations> load(Locale locale) async {
    // See the matching comment on KuMaterialLocalizationsDelegate.load --
    // same rationale for reusing English's date/number formatting here,
    // and same reason for awaiting the stock English delegate first (to
    // initialize `intl`'s date-formatting locale data as a side effect).
    await GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
    return _CupertinoLocalizationKu(
      fullYearFormat: intl.DateFormat.y('en'),
      dayFormat: intl.DateFormat.d('en'),
      weekdayFormat: intl.DateFormat.E('en'),
      mediumDateFormat: intl.DateFormat.MMMEd('en'),
      singleDigitHourFormat: intl.DateFormat('HH', 'en'),
      singleDigitMinuteFormat: intl.DateFormat.m('en'),
      doubleDigitMinuteFormat: intl.DateFormat('mm', 'en'),
      singleDigitSecondFormat: intl.DateFormat.s('en'),
      decimalFormat: intl.NumberFormat.decimalPattern('en'),
    );
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
    return SynchronousFuture<WidgetsLocalizations>(
      const _KuWidgetsLocalizations(),
    );
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<WidgetsLocalizations> old,
  ) => false;
}

/// -----------------------------------------------------------------------
/// Material
/// -----------------------------------------------------------------------
class _MaterialLocalizationKu extends MaterialLocalizationEn {
  // Can't use `super.x` parameter shorthand here because we also need to
  // override `localeName` (which has a default value in the super
  // constructor), and Dart disallows mixing super-parameter shorthand with
  // an explicit `: super(...)` call.
  // ignore: use_super_parameters
  const _MaterialLocalizationKu({
    required intl.DateFormat fullYearFormat,
    required intl.DateFormat compactDateFormat,
    required intl.DateFormat shortDateFormat,
    required intl.DateFormat mediumDateFormat,
    required intl.DateFormat longDateFormat,
    required intl.DateFormat yearMonthFormat,
    required intl.DateFormat shortMonthDayFormat,
    required intl.NumberFormat decimalFormat,
    required intl.NumberFormat twoDigitZeroPaddedFormat,
  }) : super(
         localeName: 'ku',
         fullYearFormat: fullYearFormat,
         compactDateFormat: compactDateFormat,
         shortDateFormat: shortDateFormat,
         mediumDateFormat: mediumDateFormat,
         longDateFormat: longDateFormat,
         yearMonthFormat: yearMonthFormat,
         shortMonthDayFormat: shortMonthDayFormat,
         decimalFormat: decimalFormat,
         twoDigitZeroPaddedFormat: twoDigitZeroPaddedFormat,
       );

  // Sorani Kurdish is written in the Arabic script, which -- like Arabic
  // itself (see MaterialLocalizationAr.scriptCategory) -- needs taller
  // default line-height/glyph metrics than Latin ("englishLike"). Without
  // this override Kurdish text would silently keep Latin-tuned Material
  // typography metrics.
  @override
  ScriptCategory get scriptCategory => ScriptCategory.tall;

  // --- Common actions (reuses lib/l10n/app_ku.arb wording where the same
  // concept already exists there) ------------------------------------
  @override
  String get okButtonLabel => 'باشە'; // matches ARB `ok`/`okAction`
  @override
  String get cancelButtonLabel => 'هەڵوەشاندنەوە'; // matches ARB `cancelAction`
  @override
  String get closeButtonLabel => 'داخستن'; // matches ARB `close`
  @override
  String get closeButtonTooltip => 'داخستن';
  @override
  String get saveButtonLabel => 'پاشەکەوتکردن'; // matches ARB `save`/`saveChangesButton`
  @override
  String get deleteButtonTooltip => 'سڕینەوە'; // matches ARB `deleteAction`/`deleteTooltip`
  @override
  String get backButtonTooltip => 'گەڕانەوە'; // matches ARB `backAction`
  @override
  String get continueButtonLabel => 'بەردەوامبوون';
  @override
  String get moreButtonTooltip => 'زیاتر';
  @override
  String get clearButtonTooltip => 'پاککردنەوەی دەق'; // "clear" verb matches ARB `clearFilters`/`clearAll`
  @override
  String get shareButtonLabel => 'هاوبەشکردن'; // matches ARB `shareAction`
  @override
  String get scanTextButtonLabel => 'سکانکردنی دەق';

  // --- Search ----------------------------------------------------------
  @override
  String get searchFieldLabel => 'گەڕان'; // matches ARB `search`
  @override
  String get searchWebButtonLabel => 'گەڕان لە وێب';
  @override
  String get lookUpButtonLabel => 'پشکنین';

  // --- Text-editing / selection toolbar (TextField, SelectableText --
  // used throughout the app, e.g. listing description fields, chat) ----
  @override
  String get copyButtonLabel => 'کۆپیکردن';
  @override
  String get cutButtonLabel => 'بڕین';
  @override
  String get pasteButtonLabel => 'لکاندن';
  @override
  String get selectAllButtonLabel => 'هەموو هەڵبژێرە'; // "select" verb matches ARB `select*` keys
  @override
  String? get remainingTextFieldCharacterCountOne => 'پیتێک ماوە'; // no digit, matches ARB's "one" style (e.g. `timeDaysAgo`'s `پێش ڕۆژێک`)
  @override
  String get remainingTextFieldCharacterCountOther => r'$remainingCount پیت ماوە';
  @override
  String? get remainingTextFieldCharacterCountZero => 'هیچ پیتێک نەماوە';

  // --- Date picker -------------------------------------------------------
  @override
  String get datePickerHelpText => 'بەروار هەڵبژێرە';
  @override
  String get dateInputLabel => 'بەروار بنووسە';
  @override
  String get dateRangePickerHelpText => 'مەودا هەڵبژێرە'; // "range" matches ARB `*Range` keys
  @override
  String get dateRangeStartLabel => 'بەرواری دەستپێک';
  @override
  String get dateRangeEndLabel => 'بەرواری کۆتایی';
  @override
  String get calendarModeButtonLabel => 'گۆڕین بۆ ڕۆژژمێر';
  @override
  String get inputDateModeButtonLabel => 'گۆڕین بۆ نووسین';
  @override
  String get invalidDateFormatLabel => 'شێوازی نادروست.'; // "invalid" matches ARB `yearInvalid`/`invalidPrice`
  @override
  String get dateOutOfRangeLabel => 'لە مەوداکەدا نییە.'; // matches ARB `yearOutOfRange` phrasing
  @override
  String get invalidDateRangeLabel => 'مەودای نادروست.';
  @override
  String get unspecifiedDate => 'بەروار';
  @override
  String get unspecifiedDateRange => 'مەودای بەروار';
  @override
  String get currentDateLabel => 'ئەمڕۆ'; // matches ARB `today`
  @override
  String get selectedDateLabel => 'دیاریکراو';
  @override
  String get selectYearSemanticsLabel => 'ساڵ هەڵبژێرە'; // matches ARB `selectCity`-style phrasing
  @override
  String get nextMonthTooltip => 'مانگی داهاتوو';
  @override
  String get previousMonthTooltip => 'مانگی پێشوو';

  // --- Time picker (uses ARB's existing "کاتژمێر"/"خولەک" for hour/minute,
  // see timeHoursAgo/timeMinutesAgo in app_ku.arb) -----------------------
  @override
  String get timePickerDialHelpText => 'کاتژمێر هەڵبژێرە';
  @override
  String get timePickerInputHelpText => 'کات بنووسە';
  @override
  String get timePickerHourLabel => 'کاتژمێر';
  @override
  String get timePickerMinuteLabel => 'خولەک';
  @override
  String get timePickerHourModeAnnouncement => 'کاتژمێر هەڵبژێرە';
  @override
  String get timePickerMinuteModeAnnouncement => 'خولەک هەڵبژێرە';
  @override
  String get dialModeButtonLabel => 'گۆڕین بۆ دیاڵ';
  @override
  String get inputTimeModeButtonLabel => 'گۆڕین بۆ نووسین';
  @override
  String get invalidTimeLabel => 'کاتێکی دروست بنووسە';

  // --- Paging / menus (PopupMenuButton is used throughout the app) ------
  @override
  String get nextPageTooltip => 'پەڕەی داهاتوو';
  @override
  String get previousPageTooltip => 'پەڕەی پێشوو';
  @override
  String get firstPageTooltip => 'یەکەم پەڕە';
  @override
  String get lastPageTooltip => 'کۆتا پەڕە';
  @override
  String get rowsPerPageTitle => 'ڕیز بۆ هەر پەڕەیەک:';
  @override
  String get showMenuTooltip => 'پیشاندانی مینوو';
  @override
  String get popupMenuLabel => 'مینووی دەرکەوتوو';

  // --- Dialogs / overlays / pull-to-refresh (showDialog,
  // showModalBottomSheet, and RefreshIndicator are all used throughout) --
  @override
  String get alertDialogLabel => 'ئاگاداری';
  @override
  String get dialogLabel => 'دیالۆگ';
  @override
  String get modalBarrierDismissLabel => 'لابردن';
  @override
  String get bottomSheetLabel => 'پەڕەی ژێرەوە';
  @override
  String get scrimLabel => 'پەردە';
  @override
  String get refreshIndicatorSemanticLabel => 'نوێکردنەوە';

  // --- Expand/collapse (ExpansionTile is used, e.g. Help Center FAQ) -----
  @override
  String get collapsedHint => 'فراوانکراو';
  @override
  String get expandedHint => 'کۆکراوەتەوە';
  @override
  String get collapsedIconTapHint => 'فراوانکردن';
  @override
  String get expandedIconTapHint => 'کۆکردنەوە';
  @override
  String get expansionTileCollapsedHint => 'دووجار دەست لێدان بۆ فراوانکردن';
  @override
  String get expansionTileCollapsedTapHint => 'فراوانی بکە بۆ وردەکاری زیاتر';
  @override
  String get expansionTileExpandedHint => 'دووجار دەست لێدان بۆ کۆکردنەوە';
  @override
  String get expansionTileExpandedTapHint => 'کۆکردنەوە';
}

/// -----------------------------------------------------------------------
/// Cupertino
/// -----------------------------------------------------------------------
class _CupertinoLocalizationKu extends CupertinoLocalizationEn {
  // See the matching comment on _MaterialLocalizationKu's constructor.
  // ignore: use_super_parameters
  const _CupertinoLocalizationKu({
    required intl.DateFormat fullYearFormat,
    required intl.DateFormat dayFormat,
    required intl.DateFormat weekdayFormat,
    required intl.DateFormat mediumDateFormat,
    required intl.DateFormat singleDigitHourFormat,
    required intl.DateFormat singleDigitMinuteFormat,
    required intl.DateFormat doubleDigitMinuteFormat,
    required intl.DateFormat singleDigitSecondFormat,
    required intl.NumberFormat decimalFormat,
  }) : super(
         localeName: 'ku',
         fullYearFormat: fullYearFormat,
         dayFormat: dayFormat,
         weekdayFormat: weekdayFormat,
         mediumDateFormat: mediumDateFormat,
         singleDigitHourFormat: singleDigitHourFormat,
         singleDigitMinuteFormat: singleDigitMinuteFormat,
         doubleDigitMinuteFormat: doubleDigitMinuteFormat,
         singleDigitSecondFormat: singleDigitSecondFormat,
         decimalFormat: decimalFormat,
       );

  @override
  String get alertDialogLabel => 'ئاگاداری';
  @override
  String get backButtonLabel => 'گەڕانەوە';
  @override
  String get cancelButtonLabel => 'هەڵوەشاندنەوە';
  @override
  String get clearButtonLabel => 'پاککردنەوە';
  @override
  String get copyButtonLabel => 'کۆپیکردن';
  @override
  String get cutButtonLabel => 'بڕین';
  @override
  String get pasteButtonLabel => 'لکاندن';
  @override
  String get selectAllButtonLabel => 'هەموو هەڵبژێرە';
  @override
  String get lookUpButtonLabel => 'پشکنین';
  @override
  String get searchTextFieldPlaceholderLabel => 'گەڕان';
  @override
  String get searchWebButtonLabel => 'گەڕان لە وێب';
  @override
  String get shareButtonLabel => 'هاوبەشکردن...';
  @override
  String get modalBarrierDismissLabel => 'لابردن';
  @override
  String get menuDismissLabel => 'داخستنی مینوو';
  @override
  String get noSpellCheckReplacementsLabel => 'هیچ جێگرەوەیەک نەدۆزرایەوە';
  @override
  String get todayLabel => 'ئەمڕۆ';
  @override
  String get expandedHint => 'کۆکراوەتەوە';
  @override
  String get collapsedHint => 'فراوانکراو';
  @override
  String get expansionTileCollapsedHint => 'دووجار دەست لێدان بۆ فراوانکردن';
  @override
  String get expansionTileCollapsedTapHint => 'فراوانی بکە بۆ وردەکاری زیاتر';
  @override
  String get expansionTileExpandedHint => 'دووجار دەست لێدان بۆ کۆکردنەوە';
  @override
  String get expansionTileExpandedTapHint => 'کۆکردنەوە';

  // Semantic (screen-reader) announcements for the Cupertino date/time
  // picker wheels -- not currently used by this app (no
  // CupertinoDatePicker/CupertinoTimerPicker call sites), but translated
  // for framework completeness since MaterialLocalizations is app-global.
  @override
  String? get datePickerHourSemanticsLabelOne => r'کاتژمێر $hour';
  @override
  String get datePickerHourSemanticsLabelOther => r'کاتژمێر $hour';
  @override
  String? get datePickerMinuteSemanticsLabelOne => r'خولەک $minute';
  @override
  String get datePickerMinuteSemanticsLabelOther => r'خولەک $minute';
}

/// English `WidgetsLocalizations` copy for Kurdish: [textDirection] is
/// overridden to RTL (Sorani Kurdish/Arabic script -- see class docs
/// above), and the handful of user-visible text-selection-toolbar strings
/// this class defines (copy/cut/paste/select-all/look-up/search-web/share
/// -- reachable via any TextField/SelectableText, used throughout the app)
/// are genuine Kurdish, matching [_MaterialLocalizationKu]'s wording.
/// `reorderItem*`/`radioButtonUnselectedLabel`/`noResultsFound`/
/// `searchResultsFound` are left inherited from English: this app does not
/// use `ReorderableListView` or `Radio` widgets (verified via repo-wide
/// search), so there is no reachable flow where a user would see them.
class _KuWidgetsLocalizations extends WidgetsLocalizationEn {
  const _KuWidgetsLocalizations();

  @override
  TextDirection get textDirection => TextDirection.rtl;

  @override
  String get copyButtonLabel => 'کۆپیکردن';
  @override
  String get cutButtonLabel => 'بڕین';
  @override
  String get pasteButtonLabel => 'لکاندن';
  @override
  String get selectAllButtonLabel => 'هەموو هەڵبژێرە';
  @override
  String get lookUpButtonLabel => 'پشکنین';
  @override
  String get searchWebButtonLabel => 'گەڕان لە وێب';
  @override
  String get shareButtonLabel => 'هاوبەشکردن';
}
