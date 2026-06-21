import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;
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

  Future<void> bootSellWizard(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Legacy sell step 2 opens from draft snapshot', (tester) async {
    await bootSellWizard(tester);
    await openSellDraftStep(
      tester,
      step: 1,
      carData: sellCarDataThroughStep2(),
    );

    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(find.text('Car Details'), findsWidgets);
  });

  testWidgets('Legacy sell step 3 opens from draft snapshot', (tester) async {
    await bootSellWizard(tester);
    await openSellDraftStep(
      tester,
      step: 2,
      carData: sellCarDataThroughStep3(),
    );

    expect(find.text('Step 3 of 5'), findsOneWidget);
    expect(find.text('Pricing & Contact'), findsWidgets);
  });

  testWidgets('Legacy sell step 4 opens from draft snapshot', (tester) async {
    await bootSellWizard(tester);
    await openSellDraftStep(
      tester,
      step: 3,
      carData: sellCarDataThroughStep3(),
    );

    expect(find.text('Step 4 of 5'), findsOneWidget);
    expect(find.text('Photos & Videos'), findsWidgets);
  });

  testWidgets('Legacy sell step 5 opens from draft snapshot', (tester) async {
    await bootSellWizard(tester);
    await openSellDraftStep(
      tester,
      step: 4,
      carData: sellCarDataThroughStep3(),
    );

    expect(find.text('Step 5 of 5'), findsOneWidget);
    expect(find.text('Review & Submit'), findsWidgets);
    expect(find.text('Submit Listing'), findsOneWidget);
  });
}
