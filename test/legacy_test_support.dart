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

/// Minimal step-1 sell draft fields (brand/model/trim/year).
Map<String, dynamic> sellCarDataThroughStep1() => {
      'brand': 'toyota',
      'model': 'camry',
      'trim': 'le',
      'year': '2020',
    };

/// Car data that satisfies sell step-2 validation.
Map<String, dynamic> sellCarDataThroughStep2() => {
      ...sellCarDataThroughStep1(),
      'mileage': '50000',
      'condition': 'used',
      'transmission': 'auto',
      'fuel_type': 'gas',
      'body_type': 'sedan',
      'color': 'black',
      'seating': '5',
      'drive_type': 'fwd',
      'region_specs': 'gcc',
      'title_status': 'clean',
    };

/// Car data that satisfies sell step-3 validation.
Map<String, dynamic> sellCarDataThroughStep3() => {
      ...sellCarDataThroughStep2(),
      'city': 'Erbil',
      'contact_phone': '7501234567',
    };

/// Car data that satisfies sell step-4 validation (image paths only).
Map<String, dynamic> sellCarDataThroughStep4() => {
      ...sellCarDataThroughStep3(),
      'images': <dynamic>['uploads/test_photo.jpg'],
    };

/// Draft snapshot for resuming the legacy sell wizard at [step] (0-based index).
Map<String, dynamic> sellDraftSnapshot({
  required int step,
  required Map<String, dynamic> carData,
  String draftId = 'test_sell_draft',
}) {
  return {
    'draftId': draftId,
    'currentStep': step,
    'carData': carData,
  };
}

/// Opens `/sell` with a draft snapshot and waits for the step indicator.
Future<void> openSellDraftStep(
  WidgetTester tester, {
  required int step,
  required Map<String, dynamic> carData,
}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed(
    '/sell',
    arguments: {
      'draftSnapshot': sellDraftSnapshot(step: step, carData: carData),
    },
  );
  await tester.pump();

  var ready = false;
  final stepLabel = 'Step ${step + 1} of 5';
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(stepLabel).evaluate().isNotEmpty) {
      ready = true;
      break;
    }
  }
  expect(ready, isTrue, reason: 'Sell wizard should show $stepLabel');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
