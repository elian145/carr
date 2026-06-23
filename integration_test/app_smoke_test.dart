import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import '../test/fake_api_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  testWidgets('app launches home tab', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MyApp), findsOneWidget);
  });
}
