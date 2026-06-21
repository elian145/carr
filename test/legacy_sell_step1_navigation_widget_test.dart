import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
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

  testWidgets('Legacy sell step 1 advances to step 2 when fields are set', (tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await openSellDraftStep(
      tester,
      step: 0,
      carData: {
        'brand': 'Toyota',
        'model': 'Camry',
        'trim': 'LE',
        'year': '2020',
      },
    );

    await tapNextSellStep(tester);

    var ready = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Step 2 of 5').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }

    expect(ready, isTrue, reason: 'Sell wizard should advance to step 2');
    expect(find.text('Car Details'), findsWidgets);
  });
}
