import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
