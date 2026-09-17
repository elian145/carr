// MI-01 regression tests: the Blocked Users management screen renders the
// populated/empty states from `ApiService.getBlockedUserDetails()`, and its
// Unblock action only removes a row locally after `ApiService.unblockUser()`
// actually succeeds — a failed request must leave the row in place.
import 'dart:convert';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/blocked_users_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
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

  /// Swaps in [client] for the duration of one test and restores whatever
  /// was bound before (the shared `FakeApiServer` client) afterwards —
  /// mirrors the established pattern in `api_car_detail_test.dart`.
  void useClient(MockClient client) {
    final original = ApiService.boundTestHttpClient;
    ApiService.testHttpClient = client;
    addTearDown(() => ApiService.testHttpClient = original);
  }

  testWidgets(
    'populated state renders the blocked user and an Unblock action',
    (tester) async {
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/blocked') {
            return _jsonResponse(200, {
              'blocked_users': ['pub-1'],
              'blocked_user_details': [
                {'id': 'pub-1', 'name': 'Jane Doe', 'profile_picture': null},
              ],
            });
          }
          return _jsonResponse(200, <String, dynamic>{});
        }),
      );

      await tester.pumpWidget(_wrap(const BlockedUsersPage()));
      await tester.pumpAndSettle();

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
    },
  );

  testWidgets('empty state renders when there are no blocked users', (
    tester,
  ) async {
    useClient(
      MockClient((request) async {
        if (request.url.path == '/api/users/blocked') {
          return _jsonResponse(200, {
            'blocked_users': [],
            'blocked_user_details': [],
          });
        }
        return _jsonResponse(200, <String, dynamic>{});
      }),
    );

    await tester.pumpWidget(_wrap(const BlockedUsersPage()));
    await tester.pumpAndSettle();

    expect(find.text("You haven't blocked anyone."), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets(
    'confirming Unblock calls the API once and removes the row on success',
    (tester) async {
      var unblockCalls = 0;
      useClient(
        MockClient((request) async {
          if (request.url.path == '/api/users/blocked') {
            return _jsonResponse(200, {
              'blocked_users': ['pub-1'],
              'blocked_user_details': [
                {'id': 'pub-1', 'name': 'Jane Doe', 'profile_picture': null},
              ],
            });
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/users/pub-1/unblock') {
            unblockCalls++;
            return _jsonResponse(200, {'message': 'User unblocked'});
          }
          return _jsonResponse(200, <String, dynamic>{});
        }),
      );

      await tester.pumpWidget(_wrap(const BlockedUsersPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();

      // Confirmation dialog is up; tap its own Unblock action specifically
      // (not the now-covered row button behind it).
      final dialogConfirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unblock'),
      );
      expect(dialogConfirm, findsOneWidget);
      await tester.tap(dialogConfirm);
      await tester.pumpAndSettle();

      expect(unblockCalls, 1);
      expect(find.text('Jane Doe'), findsNothing);
      expect(find.text("You haven't blocked anyone."), findsOneWidget);
    },
  );

  testWidgets('a failed Unblock call leaves the row in place', (tester) async {
    useClient(
      MockClient((request) async {
        if (request.url.path == '/api/users/blocked') {
          return _jsonResponse(200, {
            'blocked_users': ['pub-1'],
            'blocked_user_details': [
              {'id': 'pub-1', 'name': 'Jane Doe', 'profile_picture': null},
            ],
          });
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/users/pub-1/unblock') {
          return _jsonResponse(500, {'message': 'Failed to unblock user'});
        }
        return _jsonResponse(200, <String, dynamic>{});
      }),
    );

    await tester.pumpWidget(_wrap(const BlockedUsersPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();

    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Unblock'),
    );
    await tester.tap(dialogConfirm);
    await tester.pumpAndSettle();

    // Row must still be present — it is only removed after a successful
    // API response.
    expect(find.text('Jane Doe'), findsOneWidget);
  });
}
