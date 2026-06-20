import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    const carId = 'detail_test_1';
    seedCarDetailCache(carId);
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'Legacy car detail renders listing from cache when opened',
    (tester) async {
      const carId = 'detail_test_1';

      await tester.pumpWidget(const legacy.MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/car_detail', arguments: {'carId': carId});
      await tester.pump();

      var rendered = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.textContaining('Toyota').evaluate().isNotEmpty &&
            find.text('Car not found').evaluate().isEmpty) {
          rendered = true;
          break;
        }
      }

      expect(rendered, isTrue, reason: 'Car detail should render listing title');
      expect(find.text('Car not found'), findsNothing);
      expect(find.textContaining('Camry'), findsWidgets);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
