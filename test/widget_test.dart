import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_server.dart';
import 'production_test_app.dart';

void main() {
  setUpAll(() async {
    await FakeApiServer.ensureStarted();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets('ProductionApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(buildProductionTestApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
