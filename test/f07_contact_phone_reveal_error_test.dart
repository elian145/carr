// Regression tests for F-07: the Call/WhatsApp contact flow must
// distinguish "seller genuinely has no phone" (a real, empty
// contact-phone-reveal result) from a network/server/rate-limit/auth
// failure while revealing it, instead of collapsing both into the same
// "Seller phone not available" message — see PRODUCTION_AUDIT.md F-07.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Pre-existing, unrelated rendering defect in this test environment (see
/// `car_detail_error_states_test.dart` for the full explanation). Not
/// caused by, and out of scope for, this fix — filtered out here by
/// message, leaving any other, genuinely unexpected error free to fail the
/// test.
bool _isKnownPreexistingShellRenderingNoise(FlutterErrorDetails details) {
  final message = details.exceptionAsString();
  return message.contains('RenderFlex overflowed') ||
      message.contains('maxScale > minScale');
}

/// A listing whose public payload asserts a masked/available contact phone
/// (`has_contact_phone: true`) without embedding the raw phone — forcing
/// the Call/WhatsApp flow through `ApiService.getCarContactPhones` (F-07),
/// exactly like a real listing that gates raw phone numbers behind the
/// dedicated reveal endpoint (`kk/routes/cars.py::get_car_contact`).
Map<String, dynamic> _carWithMaskedPhone(String carId) => {
      'id': carId,
      'public_id': carId,
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
      'seller': {'id': 'seller_1', 'username': 'seller'},
      'has_contact_phone': true,
      'contact_phone_masked': '****4567',
    };

/// Pushes `/car_detail` for [carId] and pumps until the "Call Seller"
/// sticky button appears.
Future<void> _openCarDetail(WidgetTester tester, String carId) async {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isKnownPreexistingShellRenderingNoise(details)) return;
    originalOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalOnError);

  await tester.pumpWidget(const legacy.MyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/car_detail', arguments: {'carId': carId});
  await tester.pump();

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Call Seller').evaluate().isNotEmpty) break;
  }
}

/// Invokes the `onPressed` callback of the nearest `ButtonStyleButton`
/// ancestor of [textFinder] directly, instead of dispatching a simulated
/// tap gesture at a computed screen offset.
///
/// This test environment wraps the whole app in a display-density-locking
/// `FittedBox` (`AppResponsive.wrapApp` / `SystemDisplayLock`, unrelated to
/// F-07 and out of scope here) that makes `tester.tap`'s own coordinate-
/// based hit-test resolution unreliable for this page's buttons. Invoking
/// the callback directly is unaffected by that and still exercises the
/// exact same production code (`_callSeller`/`_openWhatsAppToSeller`/the
/// scam-warning dialog's "continue" action) that a real tap would.
///
/// Does NOT await the callback's own `Future` (some, like `_callSeller`,
/// pause on an inner `await showDialog(...)` until a later, separate
/// interaction) — returns whatever the callback itself returned so the
/// caller can await it once the whole interaction is done.
dynamic _invokeOnPressed(WidgetTester tester, Finder textFinder) {
  final buttonFinder = find.ancestor(
    of: textFinder,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(buttonFinder, findsWidgets);
  final button = tester.widget<ButtonStyleButton>(buttonFinder.first);
  final onPressed = button.onPressed;
  expect(onPressed, isNotNull, reason: 'Button should be enabled');
  return onPressed!();
}

/// Invokes [buttonLabel] ("Call Seller" / "Chat on WhatsApp"), confirms the
/// scam-safety-warning dialog ("I understand — continue"), and pumps until
/// a `SnackBar` appears.
Future<void> _invokeContactActionAndConfirmWarning(
  WidgetTester tester,
  String buttonLabel,
) async {
  // Both the sticky overlay row and the scrollable in-body row render the
  // same button/callback simultaneously in this test environment (no
  // scroll event ever flips `_showStickyButtons` to false) — either is
  // equivalent to invoke.
  final dynamic pending = _invokeOnPressed(tester, find.text(buttonLabel).first);

  // `_callSeller`/`_openWhatsAppToSeller` pause on
  // `await _confirmScamSafetyWarning()` (itself awaiting `showDialog`) —
  // let the dialog animate in before confirming it.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  final continueFinder = find.text('I understand — continue');
  expect(continueFinder, findsOneWidget);
  _invokeOnPressed(tester, continueFinder);
  await tester.pump();

  // Now let the outer callback (paused above) resume and run to completion
  // — this is where `getCarContactPhones` and the resulting snackbar are
  // actually reached.
  if (pending is Future) {
    await pending;
  }

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(SnackBar).evaluate().isNotEmpty) break;
  }
  // Let any post-frame callbacks settle without hanging on the SnackBar's
  // own auto-dismiss timer (pumpAndSettle would hang on it).
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
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
    'Call: genuine empty contact-phone result shows "Seller phone not available"',
    (tester) async {
      const carId = 'f07_call_genuine_empty';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] = () => _jsonResponse(200, {
            'contact_phone': null,
            'contact_phones': <dynamic>[],
            'has_contact_phone': false,
          });

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Call Seller');

      // findsWidgets (not findsOneWidget): Material's SnackBar transition
      // can briefly render more than one copy of its content Text during
      // its entrance animation — a framework/transition detail unrelated
      // to F-07. What matters here is that this specific "not available"
      // message is the one shown (not a generic error).
      expect(find.text('Seller phone not available'), findsWidgets);
    },
  );

  testWidgets(
    'Call: network failure shows a distinguishable error, not "Seller phone not available"',
    (tester) async {
      const carId = 'f07_call_network_error';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] =
          () => throw const SocketException('Failed host lookup');

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Call Seller');

      expect(find.text('Seller phone not available'), findsNothing);
      // Not an ApiException -> userErrorText()'s generic fallback (`loc.error`).
      expect(find.text('Error'), findsWidgets);
    },
  );

  testWidgets(
    'Call: 429 rate limit shows a distinguishable error, not "Seller phone not available"',
    (tester) async {
      const carId = 'f07_call_rate_limited';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] = () => _jsonResponse(429, {
            'message': 'Too many requests. Please try again later.',
          });

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Call Seller');

      expect(find.text('Seller phone not available'), findsNothing);
      // ApiException(429) with a short, clean message -> shown verbatim.
      expect(
        find.text('Too many requests. Please try again later.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'Call: 401 with a failed refresh shows a distinguishable error, not "Seller phone not available"',
    (tester) async {
      const carId = 'f07_call_auth_failure';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] =
          () => _jsonResponse(401, {'message': 'Token has expired'});

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Call Seller');

      expect(find.text('Seller phone not available'), findsNothing);
      // ApiException(401) -> userErrorText()'s dedicated 401 branch.
      expect(find.text('Authentication Required'), findsWidgets);
    },
  );

  testWidgets(
    'WhatsApp: network failure shows a distinguishable error, not "Seller phone not available"',
    (tester) async {
      const carId = 'f07_whatsapp_network_error';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] =
          () => throw const SocketException('Failed host lookup');

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Chat on WhatsApp');

      expect(find.text('Seller phone not available'), findsNothing);
      // Not an ApiException -> userErrorText()'s generic fallback (`loc.error`).
      expect(find.text('Error'), findsWidgets);
    },
  );

  testWidgets(
    'WhatsApp: 500 server error shows a distinguishable error, not "Seller phone not available"',
    (tester) async {
      const carId = 'f07_whatsapp_server_error';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] =
          () => _jsonResponse(500, {'message': 'Failed to get contact'});

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Chat on WhatsApp');

      expect(find.text('Seller phone not available'), findsNothing);
      // ApiException(500) with a short, clean message -> shown verbatim.
      expect(find.text('Failed to get contact'), findsWidgets);
    },
  );

  testWidgets(
    'Call and WhatsApp failures never surface as an unhandled Future exception',
    (tester) async {
      const carId = 'f07_no_unhandled_exception';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMaskedPhone(carId)});
      FakeApiServer.carContactOverrides[carId] =
          () => _jsonResponse(500, {'message': 'Failed to get contact'});

      Object? unexpectedError;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isKnownPreexistingShellRenderingNoise(details)) return;
        unexpectedError ??= details.exception;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await _openCarDetail(tester, carId);
      await _invokeContactActionAndConfirmWarning(tester, 'Call Seller');
      // Dismiss the first SnackBar before triggering the second flow so the
      // two don't visually overlap in a way that confuses the pump loop.
      await tester.pump(const Duration(seconds: 4));

      await _invokeContactActionAndConfirmWarning(tester, 'Chat on WhatsApp');

      // If either flow had let the ApiException/SocketException/etc.
      // propagate as an unhandled Future error, `flutter_test`'s own zone
      // error handling would already have failed this test before reaching
      // this assertion.
      expect(unexpectedError, isNull);
    },
  );
}
