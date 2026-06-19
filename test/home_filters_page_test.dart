import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/home_filters_page.dart';
import 'package:car_listing_app/shared/home/home_filter_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFiltersPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeFiltersPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('HomeFiltersPage loads persisted filters and shows actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      HomeFilterQuery.prefsKey: '{"brand":"Toyota","city":"Baghdad"}',
    });

    await pumpFiltersPage(tester);

    expect(find.text('Apply Filters'), findsOneWidget);
    expect(find.text('Clear Filters'), findsOneWidget);
    expect(find.text('More Filters'), findsWidgets);
    expect(find.text('Toyota'), findsOneWidget);
    expect(find.text('Baghdad'), findsWidgets);
  });

  testWidgets('HomeFiltersPage clear all resets brand selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      HomeFilterQuery.prefsKey: '{"brand":"Toyota"}',
    });

    await pumpFiltersPage(tester);
    expect(find.text('Toyota'), findsOneWidget);

    await tester.tap(find.text('Clear Filters'));
    await tester.pump();

    expect(find.text('Toyota'), findsNothing);
  });
}
