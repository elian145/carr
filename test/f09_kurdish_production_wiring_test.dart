import 'dart:ui' as ui;

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/i18n/app_locale_resolution.dart';
import 'package:car_listing_app/shared/i18n/locale_formatting.dart';
import 'package:car_listing_app/state/locale_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';

/// F-09: Kurdish must get its own Material/Cupertino/Widgets localizations
/// in the PRODUCTION app (`lib/app/production_app.dart` -> `MyApp`), not the
/// Arabic proxy that used to live in `carzo_shared.dart`, and Sorani device
/// locales (`ckb`, `ckb_IQ`, script variants) must resolve to the shipped
/// `ku` locale. These tests pump the real `MyApp` and read what the real
/// `MaterialApp` (delegates + `localeResolutionCallback`) produced.
const _ckbIq = Locale('ckb', 'IQ');
final _ckbArabIq = Locale.fromSubtags(
  languageCode: 'ckb',
  scriptCode: 'Arab',
  countryCode: 'IQ',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() {
    // No persisted `app_locale`: the device locale drives resolution unless a
    // test sets `LocaleController.currentLocale` explicitly.
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    LocaleController.currentLocale.value = null;
  });

  tearDown(() {
    LocaleController.currentLocale.value = null;
  });

  /// Pumps the production app and returns a context that lives under the
  /// app's `Localizations` (i.e. after every delegate finished loading).
  Future<BuildContext> pumpProduction(
    WidgetTester tester, {
    Locale? device,
    Locale? explicit,
  }) async {
    final dispatcher = tester.platformDispatcher;
    addTearDown(dispatcher.clearAllTestValues);
    if (device != null) {
      dispatcher.localeTestValue = device;
      dispatcher.localesTestValue = <ui.Locale>[device];
    }
    LocaleController.currentLocale.value = explicit;
    await tester.pumpWidget(const legacy.MyApp());
    for (var i = 0; i < 40 && find.byType(Navigator).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(Navigator),
      findsWidgets,
      reason: 'Localizations never finished loading',
    );
    return tester.element(find.byType(Navigator).first);
  }

  void expectKurdish(BuildContext context) {
    expect(Localizations.localeOf(context), const Locale('ku'));
    expect(Directionality.of(context), TextDirection.rtl);

    final material = MaterialLocalizations.of(context);
    expect(material, isNot(isA<MaterialLocalizationAr>()));
    expect(material.okButtonLabel, 'باشە');
    expect(material.okButtonLabel, isNot('حسنًا')); // Arabic "OK"
    expect(material.cancelButtonLabel, 'هەڵوەشاندنەوە');
    expect(material.cancelButtonLabel, isNot('إلغاء'));
    expect(material.searchFieldLabel, 'گەڕان');
    expect(material.datePickerHelpText, 'بەروار هەڵبژێرە');

    final cupertino = CupertinoLocalizations.of(context);
    expect(cupertino, isNot(isA<CupertinoLocalizationAr>()));
    expect(cupertino.todayLabel, 'ئەمڕۆ');
    expect(cupertino.todayLabel, isNot('اليوم'));
    expect(cupertino.cancelButtonLabel, 'هەڵوەشاندنەوە');

    final widgets = WidgetsLocalizations.of(context);
    expect(widgets, isNot(isA<WidgetsLocalizationAr>()));
    expect(widgets.textDirection, TextDirection.rtl);
    expect(widgets.copyButtonLabel, 'کۆپیکردن');
    expect(widgets.copyButtonLabel, isNot('نسخ'));

    // The app's own strings are Kurdish too.
    expect(AppLocalizations.of(context)!.localeName, 'ku');
  }

  group('F-09 production wiring: Kurdish gets Kurdish framework strings', () {
    testWidgets('explicit in-app `ku`', (tester) async {
      expectKurdish(await pumpProduction(tester, explicit: const Locale('ku')));
    });

    testWidgets('device `ku`', (tester) async {
      expectKurdish(await pumpProduction(tester, device: const Locale('ku')));
    });

    testWidgets('device `ckb` (bare)', (tester) async {
      expectKurdish(await pumpProduction(tester, device: const Locale('ckb')));
    });

    testWidgets('device `ckb_IQ`', (tester) async {
      expectKurdish(await pumpProduction(tester, device: _ckbIq));
    });

    testWidgets('device `ckb_Arab_IQ` (script variant)', (tester) async {
      expectKurdish(await pumpProduction(tester, device: _ckbArabIq));
    });

    testWidgets('legacy persisted `ckb` selection reads as `ku`', (
      tester,
    ) async {
      expectKurdish(await pumpProduction(tester, explicit: const Locale('ckb')));
    });
  });

  group('F-09 production wiring: ar / en / unknown are unchanged', () {
    testWidgets('explicit `ar` still gets the Arabic delegates', (
      tester,
    ) async {
      final context = await pumpProduction(
        tester,
        explicit: const Locale('ar'),
      );
      expect(Localizations.localeOf(context), const Locale('ar'));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(MaterialLocalizations.of(context), isA<MaterialLocalizationAr>());
      expect(MaterialLocalizations.of(context).okButtonLabel, 'حسنًا');
      expect(CupertinoLocalizations.of(context),
          isA<CupertinoLocalizationAr>());
      expect(WidgetsLocalizations.of(context), isA<WidgetsLocalizationAr>());
      expect(AppLocalizations.of(context)!.localeName, 'ar');
    });

    testWidgets('device `ar_EG` resolves to `ar`', (tester) async {
      final context = await pumpProduction(
        tester,
        device: const Locale('ar', 'EG'),
      );
      expect(Localizations.localeOf(context), const Locale('ar'));
      expect(MaterialLocalizations.of(context), isA<MaterialLocalizationAr>());
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('device `en_US` is English LTR', (tester) async {
      final context = await pumpProduction(
        tester,
        device: const Locale('en', 'US'),
      );
      expect(Localizations.localeOf(context), const Locale('en'));
      expect(Directionality.of(context), TextDirection.ltr);
      expect(MaterialLocalizations.of(context).okButtonLabel, 'OK');
      expect(CupertinoLocalizations.of(context).todayLabel, 'Today');
      expect(AppLocalizations.of(context)!.localeName, 'en');
    });

    testWidgets('unknown device locale falls back to English', (tester) async {
      final context = await pumpProduction(
        tester,
        device: const Locale('fr', 'FR'),
      );
      expect(Localizations.localeOf(context), const Locale('en'));
      expect(Directionality.of(context), TextDirection.ltr);
      expect(MaterialLocalizations.of(context).okButtonLabel, 'OK');
    });

    testWidgets('explicit `en` wins over a Kurdish device', (tester) async {
      final context = await pumpProduction(
        tester,
        device: _ckbIq,
        explicit: const Locale('en'),
      );
      expect(Localizations.localeOf(context), const Locale('en'));
      expect(MaterialLocalizations.of(context).okButtonLabel, 'OK');
    });
  });

  group('F-09 resolveAppLocale (the production localeResolutionCallback)', () {
    Locale resolve({Locale? explicit, Locale? device}) => resolveAppLocale(
      explicit: explicit,
      device: device,
      supported: kAppSupportedLocales,
    );

    test('supported locales are exactly en/ar/ku (ckb is not added)', () {
      expect(kAppSupportedLocales, const [
        Locale('en'),
        Locale('ar'),
        Locale('ku'),
      ]);
      expect(LocaleController.supportedCodes, ['en', 'ar', 'ku']);
    });

    test('ckb in all shapes maps to ku', () {
      for (final device in <Locale>[
        const Locale('ckb'),
        _ckbIq,
        const Locale('ckb', 'IR'),
        _ckbArabIq,
        const Locale('CKB', 'iq'),
        const Locale('ku'),
        const Locale('ku', 'IQ'),
      ]) {
        expect(resolve(device: device), const Locale('ku'), reason: '$device');
      }
    });

    test('en / ar / unknown / null resolve as before', () {
      expect(resolve(device: const Locale('en', 'US')), const Locale('en'));
      expect(resolve(device: const Locale('ar', 'IQ')), const Locale('ar'));
      expect(resolve(device: const Locale('ar')), const Locale('ar'));
      expect(resolve(device: const Locale('fr')), const Locale('en'));
      expect(resolve(device: const Locale('ckbx')), const Locale('en'));
      expect(resolve(device: null), const Locale('en'));
    });

    test('explicit selection wins over the device (ckb read as ku)', () {
      expect(
        resolve(explicit: const Locale('ar'), device: _ckbIq),
        const Locale('ar'),
      );
      expect(
        resolve(explicit: const Locale('en'), device: _ckbIq),
        const Locale('en'),
      );
      expect(
        resolve(explicit: const Locale('ckb'), device: const Locale('en')),
        const Locale('ku'),
      );
      // Unchanged legacy behaviour: an explicit value is returned verbatim.
      expect(resolve(explicit: const Locale('fr')), const Locale('fr'));
    });
  });

  group('F-09 LocaleController.resolveCode treats ckb as ku', () {
    test('explicit ckb', () {
      LocaleController.currentLocale.value = const Locale('ckb', 'IQ');
      expect(LocaleController.resolveCode(), 'ku');
      LocaleController.currentLocale.value = const Locale('ar');
      expect(LocaleController.resolveCode(), 'ar');
    });

    testWidgets('device ckb_IQ (no explicit selection)', (tester) async {
      tester.platformDispatcher.localeTestValue = _ckbIq;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      expect(LocaleController.resolveCode(), 'ku');
    });
  });

  group('F-09 Kurdish number formatting (intl has no ku/ckb data)', () {
    testWidgets('ku and ckb format numbers identically, with Western digits', (
      tester,
    ) async {
      final formatted = <String>[];
      for (final locale in <Locale>[
        const Locale('ku'),
        const Locale('ckb'),
        _ckbIq,
      ]) {
        await tester.pumpWidget(
          Localizations(
            locale: locale,
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: Builder(
              builder: (context) {
                formatted.add(
                  decimalFormatterForLocale(context).format(1234567),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      }
      expect(formatted, hasLength(3));
      for (final s in formatted) {
        expect(s, matches(RegExp(r'^[0-9][0-9,.\u066C\u066B ]*$')), reason: s);
        expect(s, isNot(matches(RegExp(r'[\u0660-\u0669\u06F0-\u06F9]'))));
      }
      expect(formatted.toSet(), hasLength(1), reason: '$formatted');
    });
  });
}
