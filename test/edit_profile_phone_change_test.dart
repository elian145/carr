// CarNet V1 fix 3 -- account phone-number change actually works.
//
// Before this fix, Edit Profile always sent `phone_number` directly to
// `PUT /api/user/profile` on every save. The real backend rejects that with
// `phone_change_verification_required` whenever the number actually
// changed, because no endpoint ever produced a compatible verification
// code -- so changing your phone number was silently impossible through the
// UI. These tests prove the new send-code -> verify dialog flow (mirroring
// the existing email-change flow) actually completes the change, and that
// resaving the SAME phone number never triggers the OTP dialog at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';

/// Repeatedly pumps short frames (rather than [WidgetTester.pumpAndSettle],
/// which can spin forever once a SnackBar's timer is pending) until [ready]
/// is true or a generous number of attempts is exhausted -- mirrors the
/// polling pattern already used by `legacy_edit_profile_widget_test.dart`.
Future<bool> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return true;
  }
  return false;
}

Future<void> _openEditProfile(WidgetTester tester) async {
  await tester.pumpWidget(const legacy.MyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/edit-profile');
  await tester.pump();

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Save Changes').evaluate().isNotEmpty) break;
  }
  // Let the push transition finish completely so the AppBar action is
  // positioned at its final, hit-testable location.
  await tester.pumpAndSettle();
  expect(
    find.text('Save Changes'),
    findsOneWidget,
    reason: 'Edit profile should have loaded with the save button visible',
  );
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
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'buyer',
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'buyer@test.com',
        'phone_number': '+9647701234567',
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

  testWidgets(
    'saving the profile with an UNCHANGED phone number never shows the verification dialog',
    (tester) async {
      await _openEditProfile(tester);

      // Phone field is the 5th TextFormField: first name, last name,
      // username, email, phone (see edit_profile_page_core.dart).
      final phoneField = find.byType(TextFormField).at(4);
      expect(tester.widget<TextFormField>(phoneField).controller?.text, '7701234567');

      // Tap the compact AppBar "Save" action -- the big "Save Changes"
      // button at the bottom of the form is scrolled out of the small test
      // viewport, so it can't be hit-tested directly.
      await tester.tap(find.byKey(const Key('editProfileSaveAction')));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.text('Edit Profile').evaluate().isEmpty,
      );

      // No OTP dialog for an unchanged number -- plain save succeeds and
      // pops immediately, exactly like before this fix.
      expect(find.text('Verify your new phone number'), findsNothing);
    },
  );

  testWidgets(
    'changing the phone number opens send-code/verify dialog and completes the change',
    (tester) async {
      await _openEditProfile(tester);

      final phoneField = find.byType(TextFormField).at(4);
      await tester.enterText(phoneField, '7709998888');
      await tester.pump();

      await tester.tap(find.byKey(const Key('editProfileSaveAction')));
      await tester.pump();
      final dialogShown = await _pumpUntil(
        tester,
        () => find.text('Verify your new phone number').evaluate().isNotEmpty,
      );
      expect(
        dialogShown,
        isTrue,
        reason: 'A changed phone number must require OTP proof before applying',
      );
      expect(find.text('Send code'), findsOneWidget);

      await tester.tap(find.text('Send code'));
      await tester.pump();
      final codeSent = await _pumpUntil(
        tester,
        () => find.text('Resend').evaluate().isNotEmpty,
      );
      expect(codeSent, isTrue, reason: 'Send code should flip the action to Resend');
      // After a code is "sent", the 6-digit code field appears.
      expect(find.byType(TextFormField).evaluate().length, greaterThan(4));

      final codeField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      expect(codeField, findsOneWidget);
      await tester.enterText(codeField, '123456');
      await tester.pump();

      await tester.tap(find.text('Verify'));
      await tester.pump();
      final applied = await _pumpUntil(
        tester,
        () => AuthService().currentUser?['phone_number'] == '+9647709998888',
      );
      expect(
        applied,
        isTrue,
        reason: 'A correct code should apply the new phone number end to end',
      );

      // Let the dialog's pop/exit animation finish -- the underlying state
      // change (and the Future `showPhoneChangeConfirmDialog` completes
      // with) lands a frame or two before the AlertDialog is fully gone.
      await _pumpUntil(
        tester,
        () => find.text('Verify your new phone number').evaluate().isEmpty,
      );

      // Dialog closed once the change went through (its own success
      // SnackBar may still be queued behind the earlier "code sent" one, so
      // this asserts on state/dialog presence rather than transient toast
      // text/timing).
      expect(find.text('Verify your new phone number'), findsNothing);
    },
  );
}
