// READ-ONLY probe: BMW X5 (and sibling SUVs) CarNet rows vs IQ runtime options.
//   flutter test tools/catalog_enrichment/iqcars/audit/x5_coupling_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

void main() {
  test('dump X5 engine/cylinder source data', () {
    final raw = File('assets/car_spec_dataset.json').readAsStringSync();
    final catalogJson = jsonDecode(
      File('assets/car_catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final overlay = IqCarsOverlay.parse(
      File('assets/car_iqcars_overlay.json').readAsStringSync(),
    );
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);
    final plain = parseCarSpecDatasetJsonString(raw).index!;
    final iq = parseCarSpecDatasetJsonString(raw).index!
      ..attachIqCarsOverlay(overlay);

    final out = StringBuffer();
    for (final bm in const [
      ('BMW', 'X5'),
      ('Toyota', 'Land Cruiser Prado'),
      ('Ford', 'Everest'),
      ('Toyota', 'Land Cruiser'),
    ]) {
      final b = bm.$1;
      final m = bm.$2;
      out.writeln('==== $b $m');
      final years = plain.yearsForCatalogStep(
        b,
        m,
        CarSpecIndex.catalogAutofillModelOnly,
      );
      out.writeln('years: $years');
      for (final y in years) {
        final vs = plain.catalogSellSpecVariants(
          b,
          m,
          CarSpecIndex.catalogAutofillModelOnly,
          y,
        );
        final combos = vs
            .map((v) =>
                '${v.engineSizeLiters?.toStringAsFixed(1)}${v.displacementSuffix}/c${v.cylinderCount}/${v.fuelType ?? v.engineType}')
            .toSet()
            .toList()
          ..sort();
        final pu = plain.sellFieldOptionsUnion(
          b,
          m,
          CarSpecIndex.catalogAutofillModelOnly,
          y,
        );
        final iu = iq.sellFieldOptionsUnion(
          b,
          m,
          CarSpecIndex.catalogAutofillModelOnly,
          y,
        );
        out.writeln(
          '$y carnet rows=${vs.length} combos=$combos\n'
          '   carnet engines=${(pu?.engineSizes.toList() ?? [])..sort()} cyl=${(pu?.cylinderCounts.toList() ?? [])..sort()}\n'
          '   runtime engines=${(iu?.engineSizes.toList() ?? [])..sort()} cyl=${(iu?.cylinderCounts.toList() ?? [])..sort()}',
        );
      }
    }
    File('tools/catalog_enrichment/iqcars/generated/x5_coupling_probe.txt')
        .writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
  });
}
