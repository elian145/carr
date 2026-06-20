import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sample listing map for car-detail widget tests (matches FakeApiServer shape).
Map<String, dynamic> sampleDetailListing([String id = 'detail_test_1']) => {
      'id': id,
      'public_id': id,
      'title': 'Test car',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'images': <dynamic>[],
      'videos': <dynamic>[],
    };

/// Seeds SharedPreferences so legacy car detail can render without waiting on network.
void seedCarDetailCache(
  String carId, {
  Map<String, dynamic>? listing,
  Map<String, dynamic> extraPrefs = const {},
}) {
  SharedPreferences.setMockInitialValues({
    'push_enabled': false,
    'cache_car_$carId': jsonEncode(listing ?? sampleDetailListing(carId)),
    ...extraPrefs,
  });
}

/// Pushes a named route on the root [Navigator] and asserts no framework errors.
Future<void> smokePushNamed(
  WidgetTester tester, {
  required String name,
  Object? args,
  Duration settleAfterOpen = const Duration(milliseconds: 350),
}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed(name, arguments: args);
  await tester.pump();
  await tester.pump(settleAfterOpen);
  await tester.pump(settleAfterOpen);
  final ex = tester.takeException();
  expect(ex, isNull, reason: 'Exception while opening route: $name');

  if (nav.canPop()) {
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final ex2 = tester.takeException();
    expect(ex2, isNull, reason: 'Exception while closing route: $name');
  }
}

/// Visits a list of production routes (guest-safe unless noted in test setup).
Future<void> smokeVisitRoutes(
  WidgetTester tester,
  Iterable<String> routes, {
  Map<String, Object?> argsByRoute = const {},
}) async {
  for (final name in routes) {
    await smokePushNamed(tester, name: name, args: argsByRoute[name]);
  }
}
