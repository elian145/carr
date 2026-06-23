import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/app/production_app.dart';

import 'fake_api_server.dart';

/// Smoke coverage for production routes via [MyApp].
void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('MyApp smoke: boot and visit app routes', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> pushNamed(String name, {Object? args}) async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(name, arguments: args);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.takeException(),
        isNull,
        reason: 'Exception while opening route: $name',
      );
      if (nav.canPop()) {
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Exception while closing route: $name',
        );
      }
    }

    await pushNamed('/sell');
    await pushNamed('/settings');
    await pushNamed('/favorites');
    await pushNamed('/chat');
    await pushNamed('/login');
    await pushNamed('/signup');
    await pushNamed('/profile');
    await pushNamed('/car_detail', args: {'carId': '1'});
    await pushNamed('/my_listings');
    await pushNamed('/comparison');
    await pushNamed('/recently-viewed');
    await pushNamed('/analytics');

    await tester.pump(const Duration(seconds: 5));
  });
}
