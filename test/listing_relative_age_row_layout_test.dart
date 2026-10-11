import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:car_listing_app/theme_provider.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

/// Layout regression: relative age must stay on the same row as the city
/// (trailing/end under the price), never as a second row below the city —
/// while Arabic plurals remain fully visible (no ellipsis).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'seller',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required Locale locale,
    required String carId,
    required Map<String, dynamic> listing,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    seedCarDetailCache(carId, listing: listing);
    FakeApiServer.carDetailOverrides[carId] = () => http.Response(
          jsonEncode({'car': listing}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    addTearDown(() => FakeApiServer.carDetailOverrides.remove(carId));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider(create: (_) => CarComparisonStore()),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('ku'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            KuMaterialLocalizationsDelegate(),
            KuWidgetsLocalizationsDelegate(),
            KuCupertinoLocalizationsDelegate(),
          ],
          home: CarDetailsPage(carId: carId),
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const ValueKey<String>('listing-relative-age'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
  }

  testWidgets(
    'Arabic: full relative age shares the city row and sits left of city',
    (tester) async {
      const carId = 'relative_age_ar_1';
      final createdAt = DateTime.now()
          .subtract(const Duration(days: 12))
          .toUtc()
          .toIso8601String();
      final listing = sampleDetailListing(carId)
        ..['city'] = 'Baghdad'
        ..['location'] = 'Baghdad'
        ..['price'] = 6555
        ..['created_at'] = createdAt;

      final expectedAge = lookupAppLocalizations(
        const Locale('ar'),
      ).timeDaysAgo(12);
      expect(expectedAge, 'قبل 12 يوماً');

      await pumpDetail(
        tester,
        locale: const Locale('ar'),
        carId: carId,
        listing: listing,
      );

      final ageFinder = find.byKey(
        const ValueKey<String>('listing-relative-age'),
      );
      expect(ageFinder, findsOneWidget);
      expect(find.text(expectedAge), findsOneWidget);
      expect(find.textContaining('يو...'), findsNothing);

      final ageBox = tester.renderObject<RenderBox>(ageFinder);
      final ageTopLeft = ageBox.localToGlobal(Offset.zero);
      final cityFinder = find.textContaining('بغداد').first;
      final cityBox = tester.renderObject<RenderBox>(cityFinder);
      final cityTopLeft = cityBox.localToGlobal(Offset.zero);

      expect(
        (ageTopLeft.dy - cityTopLeft.dy).abs(),
        lessThan(20),
        reason: 'age must share the city row (not sit below it)',
      );
      expect(
        ageTopLeft.dx,
        lessThan(cityTopLeft.dx),
        reason: 'RTL: age under price stays physically left of city',
      );
    },
  );

  testWidgets(
    'English: relative age shares the city row and sits right of city',
    (tester) async {
      const carId = 'relative_age_en_1';
      final createdAt = DateTime.now()
          .subtract(const Duration(days: 12))
          .toUtc()
          .toIso8601String();
      final listing = sampleDetailListing(carId)
        ..['city'] = 'Baghdad'
        ..['location'] = 'Baghdad'
        ..['price'] = 6555
        ..['created_at'] = createdAt;

      final expectedAge = lookupAppLocalizations(
        const Locale('en'),
      ).timeDaysAgo(12);

      await pumpDetail(
        tester,
        locale: const Locale('en'),
        carId: carId,
        listing: listing,
      );

      final ageFinder = find.byKey(
        const ValueKey<String>('listing-relative-age'),
      );
      expect(ageFinder, findsOneWidget);
      expect(find.text(expectedAge), findsOneWidget);

      final ageBox = tester.renderObject<RenderBox>(ageFinder);
      final ageTopLeft = ageBox.localToGlobal(Offset.zero);
      final cityFinder = find.textContaining('Baghdad').first;
      final cityBox = tester.renderObject<RenderBox>(cityFinder);
      final cityTopLeft = cityBox.localToGlobal(Offset.zero);

      expect((ageTopLeft.dy - cityTopLeft.dy).abs(), lessThan(20));
      expect(
        ageTopLeft.dx,
        greaterThan(cityTopLeft.dx),
        reason: 'LTR: age under price stays physically right of city',
      );
    },
  );

  testWidgets(
    'Kurdish: relative age shares the city row without ellipsis',
    (tester) async {
      const carId = 'relative_age_ku_1';
      final createdAt = DateTime.now()
          .subtract(const Duration(days: 12))
          .toUtc()
          .toIso8601String();
      final listing = sampleDetailListing(carId)
        ..['city'] = 'Erbil'
        ..['location'] = 'Erbil'
        ..['price'] = 6555
        ..['created_at'] = createdAt;

      final expectedAge = lookupAppLocalizations(
        const Locale('ku'),
      ).timeDaysAgo(12);

      await pumpDetail(
        tester,
        locale: const Locale('ku'),
        carId: carId,
        listing: listing,
      );

      expect(
        find.byKey(const ValueKey<String>('listing-relative-age')),
        findsOneWidget,
      );
      expect(find.text(expectedAge), findsOneWidget);
    },
  );
}
