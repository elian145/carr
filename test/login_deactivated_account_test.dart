// CarNet V1 fix 4 -- deactivated-account OTP login shows a real, localized
// message instead of a misleading "Invalid or expired verification code".
//
// The backend only returns `403 {"code": "account_deactivated"}` when the
// submitted OTP is genuinely correct for a deactivated account (see
// kk/routes/auth.py::_deactivated_account_otp_response). This test proves
// the Flutter login page recognizes that specific error code and shows the
// dedicated localized message, rather than falling back to the generic raw
// server-message dialog used for every other login error.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

Future<void> _openLogin(WidgetTester tester) async {
  await tester.pumpWidget(const legacy.MyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/login');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

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
    AuthService().resetTestSession();
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'a deactivated account with a correct OTP shows the deactivated message, not a generic error',
    (tester) async {
      FakeApiServer.phoneVerifyOverride = () => http.Response(
        jsonEncode({
          'message': 'This account has been deactivated. Contact support for assistance.',
          'code': 'account_deactivated',
        }),
        403,
        headers: {'content-type': 'application/json'},
      );

      await _openLogin(tester);

      await tester.enterText(find.byType(TextFormField).first, '7701234567');
      await tester.pump();

      // Tap by widget type/index (not by its text label) -- the "Send
      // code"/"Login" ElevatedButtons are declared in that order, and
      // targeting the button itself avoids ambiguity with the RenderParagraph
      // hit-testing for its label Text.
      final sendCodeButton = find.byType(ElevatedButton).first;
      await tester.ensureVisible(sendCodeButton);
      await tester.pump();
      await tester.tap(sendCodeButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.pump();

      final loginButton = find.widgetWithText(ElevatedButton, 'Login');
      await tester.ensureVisible(loginButton);
      await tester.pump();
      await tester.tap(loginButton, warnIfMissed: false);
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.text(
          'This account has been deactivated. Contact support for assistance.',
        ),
        findsOneWidget,
      );
      // Not the generic "Invalid or expired verification code" text a wrong
      // OTP would show -- proves the dedicated branch/message was used.
      expect(
        find.text('Invalid or expired verification code'),
        findsNothing,
      );
      expect(AuthService().isAuthenticated, isFalse);
    },
  );
}
