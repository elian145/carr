// READ-ONLY audit: engine labels whose scoped CarNet rows do not prove ONE fuel,
// and where the pre-fix resolver would have auto-selected one anyway.
//   flutter test tools/catalog_enrichment/iqcars/audit/fuel_inference_audit_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/models/online_spec_variant.dart';
import 'package:car_listing_app/models/sell_spec_reconcile.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';

void main() {
  test('fuel inference audit (all brand/model/year/engine combos)', () {
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

    String? fuelKey(OnlineSpecVariant v) {
      final f = (v.fuelType ?? v.engineType)?.trim();
      if (f == null || f.isEmpty) return null;
      return sellFlowFuelLabel(f).toLowerCase();
    }

    // Pre-fix resolver (verbatim rule): exact rows' raw fuels; IQ-only: the
    // same-displacement family when unanimous and diesel-ness agrees.
    String? oldFuelFor(List<OnlineSpecVariant> rows, String label) {
      final lit = OnlineSpecVariant.parseLeadingEngineLiters(label);
      if (lit == null || lit <= 0.001) return null;
      Set<String> keys(Iterable<OnlineSpecVariant> rs) =>
          {for (final r in rs) if (fuelKey(r) != null) fuelKey(r)!};
      final exact =
          rows.where((r) => OnlineSpecVariant.engineLabelOf(r) == label);
      if (exact.isNotEmpty) {
        final k = keys(exact);
        return k.length == 1 ? k.first : null;
      }
      final fam = keys(rows.where((r) =>
          r.engineSizeLiters != null && (r.engineSizeLiters! - lit).abs() < 0.06));
      if (fam.length != 1) return null;
      final isD = label.contains(' ') &&
          label.substring(label.indexOf(' ')).toUpperCase().contains('D');
      if (isD != (fam.first == 'diesel')) return null;
      return fam.first;
    }

    var combos = 0;
    var multiFuel = 0;
    var wrongBefore = 0;
    var changedAny = 0;
    final byChange = <String, int>{};
    final multiEx = <String>[];
    final wrongEx = <String>[];
    final distinctWrongLabels = <String>{};
    final distinctMultiLabels = <String>{};

    for (final brand in CarCatalog.models.keys) {
      for (final model in CarCatalog.models[brand] ?? const <String>[]) {
        final years = plain.yearsForCatalogStep(
          brand,
          model,
          CarSpecIndex.catalogAutofillModelOnly,
        );
        for (final y in years) {
          final rows = plain.catalogSellSpecVariants(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            y,
          );
          if (rows.isEmpty) continue;
          final u = iq.sellFieldOptionsUnion(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            y,
          );
          final engines = {
            ...?u?.engineSizes,
            ...rows
                .map(OnlineSpecVariant.engineLabelOf)
                .whereType<String>(),
          }..removeWhere((e) => e.isEmpty || e == 'Any');
          final core = SellSpecReconciler(
            rows: rows,
            availableEngines: engines,
            fuelKeyOf: fuelKey,
          );
          for (final e in engines) {
            combos++;
            final exact = rows
                .where((r) => OnlineSpecVariant.engineLabelOf(r) == e)
                .toList();
            final rawKeys = {
              for (final r in exact)
                if (fuelKey(r) != null) fuelKey(r)!,
            };
            final oldF = oldFuelFor(rows, e);
            final newF = core.fuelFor(e);
            final tag = '$brand $model $y "$e"';
            if (exact.isNotEmpty && rawKeys.length > 1) {
              multiFuel++;
              distinctMultiLabels.add('$brand $model "$e"');
              if (multiEx.length < 12) multiEx.add('$tag -> $rawKeys');
              // The resolver must not infer a fuel here.
              expect(newF, isNull, reason: tag);
            }
            if (oldF != newF) {
              changedAny++;
              wrongBefore++;
              byChange['${oldF ?? 'null'} -> ${newF ?? 'null'}'] =
                  (byChange['${oldF ?? 'null'} -> ${newF ?? 'null'}'] ?? 0) + 1;
              distinctWrongLabels.add('$brand $model "$e"');
              if (wrongEx.length < 25) {
                wrongEx.add('$tag old=$oldF new=$newF '
                    'rows=${exact.map((r) => '${r.engineSizeLiters}/c${r.cylinderCount}/${fuelKey(r)}').toSet()}');
              }
            }
          }
        }
      }
    }
    final out = StringBuffer()
      ..writeln('combos (brand+model+year+engine label) audited: $combos')
      ..writeln('exact rows with MORE THAN ONE fuel: $multiFuel '
          '(distinct brand+model+label: ${distinctMultiLabels.length}); '
          'resolver infers a fuel for them: 0 (asserted)')
      ..writeln('pre-fix auto-fuel that is no longer inferred / changed: '
          '$wrongBefore (distinct brand+model+label: '
          '${distinctWrongLabels.length})')
      ..writeln('change breakdown (old -> new): $byChange')
      ..writeln('\nmulti-fuel examples:')
      ..writeAll(multiEx.map((e) => '  $e\n'))
      ..writeln('\npre-fix wrong inference examples:')
      ..writeAll(wrongEx.map((e) => '  $e\n'));
    File('tools/catalog_enrichment/iqcars/generated/fuel_inference_audit.txt')
        .writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
    expect(changedAny, wrongBefore);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
