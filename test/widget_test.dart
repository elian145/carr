import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/legacy/main_legacy.dart' as legacy;

import 'fake_api_server.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('Production MyApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
