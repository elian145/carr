import 'package:car_listing_app/navigation/app_page_route.dart';
import 'package:car_listing_app/widgets/edge_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpTestApp(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => EdgeSwipeBack(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('Root page')),
      ),
    );
  }

  Future<void> pushPage(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigatorKey, {
    bool canPop = true,
  }) async {
    navigatorKey.currentState!.push(
      AppPageRoute<void>(
        builder: (_) => PopScope(
          canPop: canPop,
          child: const Scaffold(body: Text('Secondary page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragSlowly(
    WidgetTester tester, {
    required Offset start,
    required Offset offset,
  }) async {
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(offset);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('pops a secondary page after a committed edge drag', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpTestApp(tester, navigatorKey);
    await pushPage(tester, navigatorKey);

    await dragSlowly(
      tester,
      start: const Offset(1, 300),
      offset: const Offset(360, 0),
    );

    expect(find.text('Root page'), findsOneWidget);
    expect(find.text('Secondary page'), findsNothing);
  });

  testWidgets('cancels a short edge drag', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpTestApp(tester, navigatorKey);
    await pushPage(tester, navigatorKey);

    await dragSlowly(
      tester,
      start: const Offset(1, 300),
      offset: const Offset(120, 0),
    );

    expect(find.text('Secondary page'), findsOneWidget);
  });

  testWidgets('ignores horizontal drags that start outside the edge', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpTestApp(tester, navigatorKey);
    await pushPage(tester, navigatorKey);

    await dragSlowly(
      tester,
      start: const Offset(100, 300),
      offset: const Offset(400, 0),
    );

    expect(find.text('Secondary page'), findsOneWidget);
  });

  testWidgets('does nothing when the navigator is already at its root', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpTestApp(tester, navigatorKey);

    await dragSlowly(
      tester,
      start: const Offset(1, 300),
      offset: const Offset(400, 0),
    );

    expect(find.text('Root page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respects a page that blocks popping', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpTestApp(tester, navigatorKey);
    await pushPage(tester, navigatorKey, canPop: false);

    await dragSlowly(
      tester,
      start: const Offset(1, 300),
      offset: const Offset(400, 0),
    );

    expect(find.text('Secondary page'), findsOneWidget);
  });
}
