// Regression tests for F-03: locale-aware NumberFormat in the TikTok card.
//
// These exercise the public `TikTokScrollPage` (not the private
// `_TikTokListingCard`, which is a `part of` that page and cannot be
// constructed directly from a test file).
//
// Context: `lib/pages/tiktok_scroll_listing_card.dart` used to call
// `NumberFormat.decimalPattern()` with no locale argument, which always
// resolved to intl's hardcoded `en_US` default regardless of the active
// app locale. The fix reuses the project's existing
// `decimalFormatterForLocale(context)` helper
// (`lib/shared/i18n/locale_formatting.dart`), which already maps the app's
// `ku` locale to `ar` internally. This matters because intl 0.20.2 has no
// `ku` number-format data at all: calling
// `NumberFormat.decimalPattern('ku')` directly throws
// `ArgumentError: Invalid locale "ku"`. The Kurdish-locale tests below would
// fail loudly if that naive (unfixed) approach were used instead.
import 'package:car_listing_app/globals.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/tiktok_scroll_page.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the production `MaterialApp` locale wiring in
/// `lib/app/production_app.dart` (delegates + supported locales), so the
/// tests observe the same locale-resolution behavior as the real app.
Widget _wrap({
  required Locale locale,
  required List<Map<String, dynamic>> cars,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      KuMaterialLocalizationsDelegate(),
      KuWidgetsLocalizationsDelegate(),
      KuCupertinoLocalizationsDelegate(),
    ],
    home: TikTokScrollPage(cars: cars, initialIndex: 0),
  );
}

void main() {
  // Reset the mutable global currency symbol before each test so ordering
  // relative to other test files cannot affect these assertions.
  setUp(() {
    globalSymbol = r'$';
  });

  final car = <String, dynamic>{
    'title': 'Test Car',
    'price': 15000,
    'mileage': 12000,
    'year': 2020,
  };

  group('F-03: locale-aware price/mileage formatting', () {
    testWidgets('A. English locale renders price and mileage', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(locale: const Locale('en'), cars: [car]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Price call site (line ~61).
      expect(find.text(r'$15,000'), findsOneWidget);
      // Mileage call site (line ~82).
      expect(find.text('12,000 km'), findsOneWidget);
    });

    testWidgets('B. Arabic locale renders without exception', (tester) async {
      await tester.pumpWidget(_wrap(locale: const Locale('ar'), cars: [car]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(r'$15,000'), findsOneWidget);
      expect(find.text('12,000 كم'), findsOneWidget);
    });

    testWidgets(
      'C. Kurdish locale renders without exception '
      '(regression: NumberFormat.decimalPattern("ku") throws ArgumentError)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(locale: const Locale('ku'), cars: [car]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(r'$15,000'), findsOneWidget);
        expect(find.text('12,000 کم'), findsOneWidget);
      },
    );

    testWidgets(
      'E. rebuilding under a different locale updates formatted output '
      'without stale formatter state or exceptions',
      (tester) async {
        await tester.pumpWidget(
          _wrap(locale: const Locale('en'), cars: [car]),
        );
        await tester.pumpAndSettle();
        expect(find.text('12,000 km'), findsOneWidget);

        // Simulate the app-level locale switch (LocaleController rebuilds
        // MaterialApp with a new `locale:`) without introducing any new
        // locale-state infrastructure in the test itself.
        await tester.pumpWidget(
          _wrap(locale: const Locale('ku'), cars: [car]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('12,000 کم'), findsOneWidget);
        expect(find.text('12,000 km'), findsNothing);
      },
    );

    testWidgets('F. null price preserves existing symbol-only behavior', (
      tester,
    ) async {
      final noPrice = <String, dynamic>{
        'title': 'No Price Car',
        'mileage': 5000,
      };
      await tester.pumpWidget(
        _wrap(locale: const Locale('en'), cars: [noPrice]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(r'$'), findsOneWidget);
    });

    testWidgets(
      'F. non-numeric mileage preserves existing raw-string behavior',
      (tester) async {
        final rawMileage = <String, dynamic>{
          'title': 'Odd Mileage Car',
          'price': 9000,
          'mileage': 'unknown',
        };
        await tester.pumpWidget(
          _wrap(locale: const Locale('en'), cars: [rawMileage]),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('unknown km'), findsOneWidget);
      },
    );

    testWidgets('F. zero price and zero mileage remain valid', (
      tester,
    ) async {
      final zeroCar = <String, dynamic>{
        'title': 'Zero Car',
        'price': 0,
        'mileage': 0,
      };
      await tester.pumpWidget(
        _wrap(locale: const Locale('en'), cars: [zeroCar]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(r'$0'), findsOneWidget);
      expect(find.text('0 km'), findsOneWidget);
    });
  });
}
