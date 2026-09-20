// Item 8 (CarNet V1 batch): "Add to Compare" must be reachable directly
// from browse/listing cards (`buildGlobalCarCard`), reusing the exact same
// `ComparisonButton` + `CarComparisonStore` the listing details page already
// uses -- not a second implementation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/widgets/global_listing_card.dart';
import 'package:car_listing_app/features/comparison/state/car_comparison_store.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';

Map<String, dynamic> _car({String id = 'card-1'}) => <String, dynamic>{
  'id': id,
  'brand': 'Toyota',
  'model': 'Camry',
  'year': '2021',
};

Widget _harness(CarComparisonStore store, Map<String, dynamic> car) {
  return ChangeNotifierProvider<CarComparisonStore>.value(
    value: store,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: {
        '/comparison': (context) => const Scaffold(body: SizedBox()),
      },
      home: Scaffold(
        body: SizedBox(
          width: 340,
          height: 420,
          child: Builder(
            builder: (context) => buildGlobalCarCard(context, car),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'a compact compare toggle renders directly on a grid/browse listing card',
    (tester) async {
      final store = CarComparisonStore();
      await tester.pumpWidget(_harness(store, _car()));
      await tester.pump();

      expect(find.byIcon(Icons.compare_arrows_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the card compare toggle adds the listing to the shared '
    'CarComparisonStore (same store the details page reads)',
    (tester) async {
      final store = CarComparisonStore();
      await tester.pumpWidget(_harness(store, _car(id: 'card-42')));
      await tester.pump();

      expect(store.isCarInComparison('card-42'), isFalse);

      await tester.tap(find.byIcon(Icons.compare_arrows_outlined));
      await tester.pumpAndSettle();

      expect(store.isCarInComparison('card-42'), isTrue);
    },
  );

  testWidgets(
    'tapping compare again on an already-compared card navigates to the '
    'comparison page instead of duplicating the entry',
    (tester) async {
      final store = CarComparisonStore();
      store.addCarToComparison(_car(id: 'card-7'));
      await tester.pumpWidget(_harness(store, _car(id: 'card-7')));
      await tester.pump();

      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
      expect(store.comparisonCount, 1);

      await tester.tap(find.byIcon(Icons.compare_arrows));
      await tester.pumpAndSettle();

      expect(store.comparisonCount, 1);
    },
  );
}
