// F-10: the REAL home page (search/city entry bar + listing grid) and the
// search-filters page it opens, at system text scale 1.0 / 1.5 / 2.0 and
// 2.0 on a 320 dp phone. No RenderFlex overflow, the search entry stays
// tappable (opens the filters page) and the filters page's primary
// "show cars" button can be reached and hit-tested.
import 'dart:convert';

import 'package:car_listing_app/data/car_catalog_loader.dart';
import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';
import 'support/f10_scale_harness.dart';

Map<String, dynamic> _car(String id, String brand, String model) => {
      'id': id,
      'title': '$brand $model',
      'brand': brand,
      'model': model,
      'year': 2020,
      'price': 20000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
      'seller': {'id': 'seller_1', 'username': 'seller'},
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
    await CarCatalogLoader.ensureLoaded();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FakeApiServer.carsResponseOverride = (params) => http.Response(
          json.encode({
            'cars': [
              _car('h1', 'Toyota', 'Land Cruiser Prado'),
              _car('h2', 'Ford', 'Explorer'),
              _car('h3', 'Hyundai', 'Sonata'),
              _car('h4', 'Kia', 'Sportage'),
            ],
            'pagination': {'has_next': false, 'total': 4},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
  });

  tearDown(() {
    FakeApiServer.carsResponseOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required double scale,
    double width = kF10RegularWidth,
    Locale locale = const Locale('en'),
  }) async {
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: width, height: 800);
    await tester.pumpWidget(
      f10App(textScale: scale, locale: locale, home: const HomePage()),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final scale in kF10Scales) {
    testWidgets('home + search entry at ${scale}x: no overflow, tappable',
        (tester) async {
      await pumpHome(tester, scale: scale);
      expect(tester.takeException(), isNull);

      final searchIcon = find.byIcon(Icons.search).first;
      expect(searchIcon.hitTestable(), findsOneWidget,
          reason: 'search entry must be hit-testable at $scale');
      await tester.tap(searchIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Search Cars'), findsOneWidget);

      // Primary action of the filters page.
      final show = find.byType(ElevatedButton);
      expect(show, findsWidgets);
      await tester.ensureVisible(show.first);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(show.first.hitTestable(), findsOneWidget,
          reason: 'show-cars CTA must be hit-testable at $scale');

      // Submit: the home feed then renders the listing grid at this scale.
      await tester.tap(show.first);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('Sonata').evaluate().isNotEmpty) break;
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Sonata'), findsWidgets);
    });
  }

  testWidgets('home + filters at 2.0x on a 320 dp phone: no overflow',
      (tester) async {
    await pumpHome(tester, scale: 2.0, width: kF10NarrowWidth);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home at 2.0x in Arabic / RTL: no overflow', (tester) async {
    await pumpHome(tester, scale: 2.0, locale: const Locale('ar'));
    expect(tester.takeException(), isNull);
  });
}
