// F-10: the REAL listing detail page (hero title sheet, price row, meta row,
// specs grid, CTA stack, similar-listings area) at system text scale
// 1.0 / 1.5 / 2.0, 2.0 on a 320 dp phone, and Arabic/RTL at 2.0.
//
// Asserts no RenderFlex overflow while scrolling the whole page, the title /
// price really grow, and that the primary CTAs (contact / compare / chat) can
// be scrolled into view and are hit-testable.
import 'dart:convert';

import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/features/comparison/widgets/comparison_button.dart';
import 'package:car_listing_app/features/listing/widgets/car_details_contact_bar.dart';
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';
import 'support/f10_scale_harness.dart';

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
        'username': 'viewer',
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

  var seq = 0;

  Future<String> pumpDetail(
    WidgetTester tester, {
    required double scale,
    double width = kF10RegularWidth,
    Locale locale = const Locale('en'),
    String model = 'Camry Hybrid Premium Edition',
  }) async {
    final carId = 'f10_detail_${seq++}';
    await f10LoadFonts(tester);
    f10SetWindow(tester, width: width, height: 800);

    final listing = sampleDetailListing(carId)
      ..['model'] = model
      ..['city'] = locale.languageCode == 'ar' ? 'بغداد' : 'Baghdad'
      ..['location'] = locale.languageCode == 'ar' ? 'بغداد' : 'Baghdad'
      ..['price'] = 48500
      ..['created_at'] = DateTime.now()
          .subtract(const Duration(days: 12))
          .toUtc()
          .toIso8601String()
      ..['mileage'] = 123456
      ..['trim'] = 'XLE Premium'
      ..['transmission'] = 'automatic'
      ..['fuel_type'] = 'gasoline'
      ..['contact_phone'] = '07501234567';
    seedCarDetailCache(carId, listing: listing);
    FakeApiServer.carDetailOverrides[carId] = () => http.Response(
          jsonEncode({'car': listing}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    addTearDown(() => FakeApiServer.carDetailOverrides.remove(carId));

    await f10Pump(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider(create: (_) => CarComparisonStore()),
        ],
        child: f10App(
          textScale: scale,
          locale: locale,
          home: CarDetailsPage(carId: carId),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ComparisonButton).evaluate().isNotEmpty) break;
    }
    return carId;
  }

  /// The detail body is a lazily-built sliver: drag the page until [target]
  /// exists and is on screen (asserting no exception on every frame).
  Future<void> scrollTo(WidgetTester tester, Finder target,
      {bool up = false}) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 40; i++) {
      if (target.evaluate().isNotEmpty &&
          f10IsOnScreen(tester, target.first)) {
        return;
      }
      await tester.drag(scrollable, Offset(0, up ? 250 : -250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    fail('could not scroll $target into view');
  }

  Finder modelText() => find.textContaining('Camry').first;

  for (final scale in kF10Scales) {
    testWidgets('detail page at ${scale}x: no overflow, CTAs reachable',
        (tester) async {
      await pumpDetail(tester, scale: scale);
      expect(tester.takeException(), isNull);
      expect(modelText(), findsOneWidget);
      expect(find.textContaining('48,500'), findsWidgets);

      // Scroll the whole page; every frame must be exception-free.
      await scrollTo(tester, find.byType(ComparisonButton));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final cmp = find.descendant(
        of: find.byType(ComparisonButton),
        matching: find.byType(OutlinedButton),
      );
      expect(cmp.hitTestable(), findsWidgets,
          reason: 'compare CTA must be hit-testable at $scale');

      {
        await scrollTo(tester, find.byType(CarDetailsContactBar), up: true);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find
              .descendant(
                of: find.byType(CarDetailsContactBar),
                matching: find.byType(ElevatedButton),
              )
              .hitTestable(),
          findsWidgets,
        );
      }
    });
  }

  testWidgets('title (model) and price really scale: taller at 2.0x',
      (tester) async {
    await pumpDetail(tester, scale: 1.0);
    final h1 = tester.getSize(modelText()).height;
    final p1 = tester.getSize(find.textContaining('48,500').first).height;
    await pumpDetail(tester, scale: 2.0);
    expect(tester.takeException(), isNull);
    final h2 = tester.getSize(modelText()).height;
    final p2 = tester.getSize(find.textContaining('48,500').first).height;
    expect(h2, greaterThan(h1 * 1.5), reason: 'model $h1 -> $h2');
    expect(p2, greaterThan(p1 * 1.5), reason: 'price $p1 -> $p2');
  });

  testWidgets('2.0x on a 320 dp phone with a long model name: no overflow',
      (tester) async {
    await pumpDetail(
      tester,
      scale: 2.0,
      width: kF10NarrowWidth,
      model: 'Camry Hybrid Premium Edition Grand Touring Package',
    );
    expect(tester.takeException(), isNull);
    await scrollTo(tester, find.byType(ComparisonButton));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic / RTL at 2.0x: no overflow', (tester) async {
    await pumpDetail(tester, scale: 2.0, locale: const Locale('ar'));
    expect(tester.takeException(), isNull);
    await scrollTo(tester, find.byType(ComparisonButton));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
