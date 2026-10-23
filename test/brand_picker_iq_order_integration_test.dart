// Integration of the brand-logo fixes with IQ Cars source priority.
//
// Drives the REAL Search Cars page at the Samsung A17 viewport with the real
// bundled catalog and IQ overlay, so the grid has the production order
// (IQ Cars brands first, CarNet-only brands after). Checks that the new order
// keeps the four-column grid and the 52 dp circular logos intact and that no
// brand is lost, duplicated or renamed.
import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_server.dart';
import 'support/brand_picker_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });
  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'Search picker keeps IQ-first order with four columns and 52 dp coins',
    (tester) async {
      final key = GlobalKey();
      await pumpSearchBrandPicker(tester, boundaryKey: key);

      // Sanity: the real catalog + IQ provenance are loaded (otherwise this
      // test would silently check the bare embedded list). Today every one of
      // the 146 catalog brands is also an IQ Cars brand, so brand-level source
      // priority is order-preserving; the partition checks below still hold if
      // CarNet-only brands are ever added.
      expect(CarCatalog.brands.length, CarCatalog.baselineBrands.length);
      expect(CarCatalog.brands.where(CarCatalog.isIqBrand), isNotEmpty);

      final grid = find.byType(GridView).first;
      final scrollable = find.descendant(
        of: grid,
        matching: find.byType(Scrollable),
      );
      await tester.ensureVisible(grid);
      await settle(tester, frames: 2);
      await rewindGrid(tester);

      // brand -> (absolute y inside the grid, tile left, coin size)
      final seen = <String, ({double y, double x, Size coin})>{};
      void collect() {
        final pixels = tester.state<ScrollableState>(scrollable.first).position.pixels;
        final gridTop = tester.getRect(grid).top;
        for (final e in find.byType(BrandLogoCircle).evaluate()) {
          final w = e.widget as BrandLogoCircle;
          final coin = tester.getRect(
            find.descendant(
              of: find.byElementPredicate((x) => identical(x, e)),
              matching: find.byType(ClipOval),
            ),
          );
          final tile = tester.getRect(
            find.ancestor(
              of: find.byElementPredicate((x) => identical(x, e)),
              matching: find.byType(InkWell),
            ).first,
          );
          seen.putIfAbsent(
            w.brand,
            () => (y: pixels + tile.top - gridTop, x: tile.left, coin: coin.size),
          );
        }
      }

      collect();
      for (var i = 0; i < 80; i++) {
        final before = seen.length;
        await tester.drag(grid, const Offset(0, -150));
        await settle(tester, frames: 2);
        collect();
        if (i > 20 && seen.length == before) break;
      }

      final inGridOrder = seen.entries.toList()
        ..sort((a, b) {
          final dy = a.value.y.round().compareTo(b.value.y.round());
          return dy != 0 ? dy : a.value.x.compareTo(b.value.x);
        });
      final order = inGridOrder.map((e) => e.key).toList();

      // Nothing lost, nothing duplicated, nothing renamed.
      expect(order.toSet().length, order.length, reason: 'duplicate brand tile');
      expect(
        order,
        equals(CarCatalog.brands),
        reason: 'the Search grid must list exactly CarCatalog.brands, in order',
      );
      expect(
        order.toSet(),
        equals(CarCatalog.baselineBrands.toSet()),
        reason: 'source priority only reorders: same brand set as the baseline',
      );

      // IQ Cars brands first, CarNet-only brands after (and still present).
      final iq = order.where(CarCatalog.isIqBrand).toList();
      final carnetOnly = order.where((b) => !CarCatalog.isIqBrand(b)).toList();
      expect(iq, isNotEmpty);
      expect(
        order.take(iq.length).toList(),
        equals(iq),
        reason: 'every IQ Cars brand must come before every CarNet-only brand',
      );
      expect(
        order.skip(iq.length).toList(),
        equals(carnetOnly),
        reason: 'CarNet-only brands stay available after the IQ Cars ones',
      );
      for (final b in const [
        'Huanghai',
        'KAWEI',
        'Polarsun',
        'Zimmer',
        'Zyle Daewoo Commercial Vehicle',
      ]) {
        expect(order, contains(b), reason: '$b must stay selectable');
      }

      // The four-column grid and the 52 dp circles survive the reordering.
      final columns = seen.values.map((v) => v.x.round()).toSet();
      expect(columns.length, 4, reason: 'columns at x=$columns');
      final bad = <String>[
        for (final e in seen.entries)
          if ((e.value.coin.width - 52).abs() > 0.01 ||
              (e.value.coin.height - 52).abs() > 0.01)
            '${e.key}: ${e.value.coin}',
      ];
      expect(bad, isEmpty, reason: bad.join(', '));
    },
  );
}
