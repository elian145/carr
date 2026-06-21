import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Legacy fallback route builders smoke', (tester) async {
    final routes = legacy.buildLegacyFallbackRoutes();
    expect(routes.keys, contains('/legacy_home'));
    expect(routes.keys, contains('/legacy_car_detail'));

    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> openBuilder(
      String name,
      WidgetBuilder builder, {
      Object? args,
    }) async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name, arguments: args),
          builder: builder,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      final ex = tester.takeException();
      expect(ex, isNull, reason: 'Exception opening $name');

      if (nav.canPop()) {
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final ex2 = tester.takeException();
        expect(ex2, isNull, reason: 'Exception closing $name');
      }
    }

    await openBuilder('/legacy_home', routes['/legacy_home']!);
    await openBuilder('/legacy_settings', routes['/legacy_settings']!);
    await openBuilder('/legacy_login', routes['/legacy_login']!);
    await openBuilder('/legacy_comparison', routes['/legacy_comparison']!);
    await openBuilder('/legacy_favorites', routes['/legacy_favorites']!);
    await openBuilder('/legacy_profile', routes['/legacy_profile']!);
    await openBuilder(
      '/legacy_saved_searches',
      routes['/legacy_saved_searches']!,
    );
    await openBuilder(
      '/legacy_car_detail',
      routes['/legacy_car_detail']!,
      args: {'carId': '1'},
    );
    await openBuilder('/legacy_sell', routes['/legacy_sell']!);
  });
}
