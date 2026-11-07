// F-44: pages must not call setState after being disposed while an async
// load is still in flight (success or failure).
import 'dart:async';
import 'dart:convert';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/dealer_profile_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Completer<http.Response> gate;
  late int requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    gate = Completer<http.Response>();
    requests = 0;
    ApiService.testHttpClient = MockClient((request) {
      if (request.url.path.contains('dealer')) {
        requests++;
        return gate.future;
      }
      return Future.value(http.Response('{}', 200,
          headers: {'content-type': 'application/json'}));
    });
  });

  tearDown(() {
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
  });

  Widget host(Widget child) => ChangeNotifierProvider<AuthService>.value(
    value: AuthService(),
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  Future<void> disposeThenComplete(
    WidgetTester tester,
    http.Response response,
  ) async {
    await tester.pumpWidget(
      host(const DealerProfilePage(dealerPublicId: 'dealer_x')),
    );
    await tester.pump();
    expect(requests, greaterThan(0), reason: 'load must be in flight');
    // Navigate away: the page is disposed while the request is pending.
    await tester.pumpWidget(host(const SizedBox()));
    gate.complete(response);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(minutes: 3)); // drain request timers
  }

  testWidgets('dealer profile: success arriving after dispose does not throw',
      (tester) async {
    await disposeThenComplete(
      tester,
      http.Response(
        json.encode({
          'dealer': {'id': 'dealer_x', 'name': 'X'},
          'listings': <dynamic>[],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dealer profile: failure arriving after dispose does not throw',
      (tester) async {
    await disposeThenComplete(
      tester,
      http.Response('{"message":"boom"}', 500,
          headers: {'content-type': 'application/json'}),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative control: page still renders its result when mounted',
      (tester) async {
    await tester.pumpWidget(
      host(const DealerProfilePage(dealerPublicId: 'dealer_x')),
    );
    await tester.pump();
    gate.complete(
      http.Response(
        json.encode({
          'dealer': {'public_id': 'dealer_x', 'dealership_name': 'Mounted Dealer'},
          'listings': <dynamic>[],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Mounted Dealer'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 3));
  });
}
