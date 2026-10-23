import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';
import 'package:car_listing_app/data/car_name_translations.dart';
import 'package:car_listing_app/features/home/home_filters_query.dart';
import 'package:car_listing_app/features/home/home_vehicle_spec_options.dart';
import 'package:car_listing_app/features/sell/sell_listing_payload.dart';
import 'package:car_listing_app/services/car_spec_index.dart';
import 'package:car_listing_app/services/iqcars_overlay.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';

/// Source-priority ordering of the vehicle pickers: IQ Cars entries first, then
/// CarNet-only entries, no entry removed or renamed, identical for Sell /
/// Edit Listing / Search. Real bundled assets (catalog, spec dataset, overlay
/// and the IQ provenance asset) throughout; synthetic catalogs only where the
/// bundled catalog has no CarNet-only brand/model to exercise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String specRaw;
  late String overlayRaw;
  late String provenanceRaw;
  late Map<String, dynamic> catalogJson;
  late Map<String, dynamic> provenanceJson;
  late IqCarsOverlay overlay; // overlay + provenance (what the app loads)
  late IqCarsOverlay overlayNoProvenance; // provenance asset unavailable
  late CarSpecIndex plainIdx;
  late CarSpecIndex iqIdx;

  const searchCylinderDefaults = [
    'Any', '1', '2', '3', '4', '5', '6', '8', '10', '12', '16', //
  ];
  const sellCylinderDefaults = ['3', '4', '5', '6', '8', '10', '12'];

  /// Models the task names explicitly plus other representative ones.
  const representative = <(String, String)>[
    ('Toyota', 'Corolla'),
    ('Toyota', 'Corolla Cross'),
    ('Toyota', 'Land Cruiser'),
    ('Toyota', 'Land Cruiser Prado'),
    ('Toyota', 'Camry'),
    ('Ford', 'Everest'),
    ('Nissan', 'Patrol'),
    ('BMW', '5-Series'),
    ('BMW', '4-Series'),
    ('Honda', 'Civic'),
    ('Alfa Romeo', 'Mito'),
  ];

  /// Independent oracle: same folding rules as the spec (case, '-', '_',
  /// whitespace), written separately from the production helper.
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[-_]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  bool provHasModel(String b, String m) {
    for (final be in provenanceJson.entries) {
      if (be.key.startsWith('_') || norm(be.key) != norm(b)) continue;
      for (final me in (be.value as Map).keys) {
        if (norm(me.toString()) == norm(m)) return true;
      }
    }
    return false;
  }

  bool provHasBrand(String b) =>
      provenanceJson.keys.any((k) => !k.startsWith('_') && norm(k) == norm(b));

  setUpAll(() {
    specRaw = File('assets/car_spec_dataset.json').readAsStringSync();
    overlayRaw = File('assets/car_iqcars_overlay.json').readAsStringSync();
    provenanceRaw = File('assets/car_iqcars_provenance.json').readAsStringSync();
    catalogJson = jsonDecode(File('assets/car_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    provenanceJson = jsonDecode(provenanceRaw) as Map<String, dynamic>;
    overlay = IqCarsOverlay.parse(overlayRaw, provenanceRaw: provenanceRaw);
    overlayNoProvenance = IqCarsOverlay.parse(overlayRaw);
    plainIdx = parseCarSpecDatasetJsonString(specRaw).index!;
    iqIdx = parseCarSpecDatasetJsonString(specRaw).index!
      ..attachIqCarsOverlay(overlay);
  });

  setUp(() {
    CarCatalog.resetCatalogOverrideForTest();
    CarCatalog.applyCatalogFromAsset(catalogJson);
    CarCatalog.applyIqCarsOverlay(overlay);
  });

  tearDown(() {
    CarCatalog.resetCatalogOverrideForTest();
    CarNameTranslations.debugResetForTest();
  });

  HomeVehicleFieldDefaults defaults() => const HomeVehicleFieldDefaults(
        bodyTypes: ['Any', 'SUV'],
        transmissions: ['Any', 'Automatic', 'Manual'],
        fuelTypes: ['Any', 'Gasoline', 'Diesel'],
        driveTypes: ['Any', 'FWD', 'RWD', 'AWD', '4WD'],
        cylinderCounts: searchCylinderDefaults,
        seatings: ['Any', '5'],
        engineSizes: ['Any', 'generic-engine-ladder'],
      );

  /// Search exactly as the Search screen resolves it for Brand + Model.
  HomeVehicleFieldOptions search(CarSpecIndex idx, String b, String m) {
    final ctx = HomeVehicleContext(brand: b, model: m, trim: '');
    return HomeVehicleFieldOptions.resolve(
      catalog: resolveHomeVehicleCatalogOptions(idx, ctx),
      engineCatalog: resolveHomeVehicleEngineCatalogOptions(idx, ctx),
      defaults: defaults(),
      vehicleResolved: true,
    );
  }

  /// Sell step 2's catalog option set for Brand + Model (model level).
  CatalogSellFieldOptions? sellOpts(CarSpecIndex idx, String b, String m) =>
      idx.hasCoverage(b, m)
          ? idx.sellFieldOptionsUnion(
              b, m, CarSpecIndex.catalogAutofillModelOnly, 2020)
          : idx.iqOnlyFieldOptions(b, m, CarSpecIndex.catalogAutofillModelOnly);

  List<String> sellEngines(CarSpecIndex idx, String b, String m) {
    final o = sellOpts(idx, b, m);
    if (o == null || o.engineSizes.isEmpty) return const <String>[];
    return sortCatalogEngineSizeLabels(o.engineSizes, iqLabels: o.iqEngineSizes);
  }

  List<String> sellCylinders(CarSpecIndex idx, String b, String m) {
    final o = sellOpts(idx, b, m);
    return narrowCylinderOptionsToCatalog(
      sellCylinderDefaults,
      o?.cylinderCounts,
      o?.iqCylinderCounts,
    );
  }

  /// Independent oracle: stable partition by a predicate.
  (List<T>, List<T>) split<T>(List<T> xs, bool Function(T) isIq) =>
      (xs.where(isIq).toList(), xs.where((x) => !isIq(x)).toList());

  // ---------------------------------------------------------------- provenance
  group('provenance asset', () {
    test('is loaded with the overlay and describes every bundled brand / model', () {
      expect(overlay.hasProvenance, isTrue);
      expect((provenanceJson['_meta'] as Map)['kind'], 'iqcars_provenance');
      final brands = (catalogJson['brands'] as List).cast<String>();
      final models = (catalogJson['models'] as Map).cast<String, dynamic>();
      for (final b in brands) {
        expect(CarCatalog.isIqBrand(b), isTrue, reason: b);
        for (final m in (models[b] as List).cast<String>()) {
          expect(CarCatalog.isIqModel(b, m), isTrue, reason: '$b $m');
        }
      }
    });

    test('every approved addition belongs to an exactly matched IQ model', () {
      for (final b in overlay.entries) {
        for (final m in b.value.keys) {
          expect(CarCatalog.isIqModel(b.key, m), isTrue, reason: '${b.key} $m');
        }
      }
    });

    test('identities fold case, hyphen / underscore / spacing only', () {
      expect(CarCatalog.isIqBrand('mercedes benz'), isTrue);
      expect(CarCatalog.isIqBrand('MERCEDES-BENZ'), isTrue);
      expect(CarCatalog.isIqBrand('Land-Rover'), isTrue);
      expect(CarCatalog.isIqModel('BMW', '3 Series'), isTrue);
      expect(CarCatalog.isIqModel('bmw', '3-series'), isTrue);
      expect(CarCatalog.isIqModel('Toyota', 'land  cruiser'), isTrue);
      // Look-alikes are different identities.
      expect(CarCatalog.isIqModel('Toyota', 'Corolla Crossover'), isFalse);
      expect(CarCatalog.isIqModel('Toyota', 'Land Cruiser FJ'), isFalse);
      expect(CarCatalog.isIqModel('Toyota', 'Corolla Concept'), isFalse);
      expect(CarCatalog.isIqBrand('Toyot'), isFalse);
      expect(CarCatalog.isIqBrand(null), isFalse);
      expect(CarCatalog.isIqModel('Toyota', null), isFalse);
      expect(CarCatalog.isIqModel('Zeta Motors', 'Z1'), isFalse);
    });

    test('Land Cruiser and Land Cruiser Prado never share trim identities', () {
      // GXR is an IQ trim of the Prado but only a CarNet trim of the Land Cruiser
      // (IQ's "GX.R" was held, never merged with "GXR").
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser Prado', 'GXR'), isTrue);
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser', 'GXR'), isFalse);
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser', 'GX'), isTrue);
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser Prado', 'GX'), isTrue,
          reason: 'GX is an approved IQ addition of the Prado');
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser Prado', 'EXR'), isFalse);
      // Trim identity is the exact name: only case / spacing are folded.
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser', 'gx'), isTrue);
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser', 'G X'), isFalse);
      expect(CarCatalog.isIqTrim('Toyota', 'Land Cruiser', 'GX.R'), isFalse);
      expect(CarCatalog.isIqTrim('Toyota', 'Corolla', 'IM'), isFalse);
    });

    test('parsing is fail-safe: wrong kind, garbage or absence means "no provenance"', () {
      expect(parseIqProvenanceText('not json'), isEmpty);
      expect(parseIqProvenanceText('{"Toyota":{"Corolla":{}}}'), isEmpty,
          reason: 'no _meta.kind');
      expect(parseIqProvenanceText(overlayRaw), isEmpty,
          reason: 'the overlay is not a provenance asset');
      expect(
        IqCarsOverlay.parse(overlayRaw, provenanceRaw: 'garbage').hasProvenance,
        isFalse,
      );
      expect(overlayNoProvenance.hasProvenance, isFalse);
      expect(overlayNoProvenance.modelCount, 1558);
      expect(IqCarsOverlay.empty.hasProvenance, isFalse);
    });
  });

  // ------------------------------------------------------------ brands / models
  group('brands and models', () {
    test('the bundled catalog has an IQ identity for every entry, so nothing moves', () {
      // Every bundled brand and model is also an IQ Cars brand / model, so the
      // IQ-first partition is the identity here and the lists are untouched.
      expect(CarCatalog.brands, CarCatalog.baselineBrands);
      for (final e in CarCatalog.baselineModels.entries) {
        expect(CarCatalog.models[e.key], e.value, reason: e.key);
      }
      expect(identical(CarCatalog.brands, CarCatalog.baselineBrands), isTrue,
          reason: 'rule 6: nothing to reorder -> the very same list');
    });

    Map<String, dynamic> remoteCatalog() {
      final baseBrands = (catalogJson['brands'] as List).cast<String>();
      final models = <String, List<String>>{
        for (final e in (catalogJson['models'] as Map).entries)
          e.key.toString(): List<String>.of((e.value as List).cast<String>()),
      };
      final toyota = models['Toyota']!;
      models['Toyota'] = [
        'ZZ CarNet Model', // CarNet-only, listed first by the remote catalog
        'Corolla-Cross', // formatting alias of the IQ model "Corolla Cross"
        ...toyota.take(20),
        'Corolla Concept', // CarNet-only lookalike
        'Corolla Crossover', // CarNet-only lookalike
        ...toyota.skip(20),
      ];
      models['Zeta Motors'] = ['Z1', 'A1']; // brand IQ Cars does not have
      models['Alpha CarNet'] = ['Only'];
      final trims = <String, dynamic>{
        for (final e in (catalogJson['trimsByBrandModel'] as Map).entries)
          e.key.toString():
              Map<String, dynamic>.of((e.value as Map).cast<String, dynamic>()),
      };
      (trims['Toyota'] as Map<String, dynamic>)['ZZ CarNet Model'] = [
        'Zed', 'Alpha', 'Other', //
      ];
      return {
        'brands': ['Zeta Motors', ...baseBrands, 'Alpha CarNet'],
        'models': models,
        'trimsByBrandModel': trims,
      };
    }

    test('IQ brands first, CarNet-only brands after; nothing added, dropped or renamed', () {
      CarCatalog.applyCatalogFromAsset(remoteCatalog());
      final base = CarCatalog.baselineBrands;
      expect(base.first, 'Zeta Motors');
      final brands = CarCatalog.brands;
      expect(brands.length, base.length);
      expect(brands.toSet(), base.toSet());
      expect(brands.toSet().length, brands.length, reason: 'each appears once');
      final (iq, carnet) = split(base, provHasBrand);
      expect(carnet, ['Zeta Motors', 'Alpha CarNet']);
      expect(brands, [...iq, ...carnet]);
      expect(brands.sublist(0, 146), (catalogJson['brands'] as List).cast<String>(),
          reason: 'IQ group keeps the existing order');
      expect(brands.last, 'Alpha CarNet',
          reason: 'CarNet-only keeps its own relative order, not alphabetised');
    });

    test('models: IQ models first, CarNet-only after, per brand', () {
      CarCatalog.applyCatalogFromAsset(remoteCatalog());
      final base = CarCatalog.baselineModels['Toyota']!;
      final ordered = CarCatalog.models['Toyota']!;
      expect(ordered.length, base.length);
      expect(ordered.toSet(), base.toSet());
      final (iq, carnet) = split(base, (m) => provHasModel('Toyota', m));
      expect(carnet, [
        'ZZ CarNet Model', 'Corolla Concept', 'Corolla Crossover', //
      ]);
      expect(ordered, [...iq, ...carnet]);
      // formatting alias is an IQ model and keeps its own spelling
      expect(ordered.first, 'Corolla-Cross');
      expect(ordered, contains('Corolla Cross'));
      expect(ordered.indexOf('Corolla'), lessThan(ordered.indexOf('Corolla Concept')));
      expect(ordered.indexOf('Corolla Cross'),
          lessThan(ordered.indexOf('Corolla Crossover')));
      // canonical values untouched
      expect(ordered.where((m) => m.startsWith('Land Cruiser')).toSet(),
          base.where((m) => m.startsWith('Land Cruiser')).toSet());
    });

    test('rule 6: a brand IQ Cars does not have keeps its CarNet order exactly', () {
      CarCatalog.applyCatalogFromAsset(remoteCatalog());
      expect(CarCatalog.models['Zeta Motors'], ['Z1', 'A1']);
      expect(CarCatalog.models['Alpha CarNet'], ['Only']);
      expect(CarCatalog.isIqBrand('Zeta Motors'), isFalse);
      // a model IQ does not have keeps its trims untouched too
      expect(CarCatalog.trimsFor('Toyota', 'ZZ CarNet Model'),
          ['Zed', 'Alpha', 'Other']);
    });

    test('brand formatting aliases join the IQ group and keep their spelling', () {
      CarCatalog.applyCatalogFromAsset({
        'brands': ['Zeta Motors', 'mercedes benz', 'TOYOTA', 'Alpha CarNet'],
      });
      expect(CarCatalog.brands,
          ['mercedes benz', 'TOYOTA', 'Zeta Motors', 'Alpha CarNet']);
    });

    test('derived lists are cached and rebuilt when the catalog changes', () {
      CarCatalog.applyCatalogFromAsset(remoteCatalog());
      expect(identical(CarCatalog.brands, CarCatalog.brands), isTrue);
      expect(identical(CarCatalog.models, CarCatalog.models), isTrue);
      final before = CarCatalog.brands;
      // re-applying the (already prioritised) lists is idempotent
      CarCatalog.applyCatalogFromAsset({
        'brands': CarCatalog.brands,
        'models': CarCatalog.models,
      });
      expect(CarCatalog.brands, before);
      // ... and an unrelated catalog is not served from a stale cache
      CarCatalog.applyCatalogFromAsset({'brands': ['Zeta Motors', 'Toyota']});
      expect(CarCatalog.brands, ['Toyota', 'Zeta Motors']);
    });

    test('without the provenance asset every list keeps its existing order', () {
      CarCatalog.applyCatalogFromAsset(remoteCatalog());
      CarCatalog.applyIqCarsOverlay(overlayNoProvenance);
      expect(CarCatalog.brands.first, 'Zeta Motors');
      expect(identical(CarCatalog.brands, CarCatalog.baselineBrands), isTrue);
      expect(CarCatalog.models['Toyota']!.first, 'ZZ CarNet Model');
      expect(identical(CarCatalog.models, CarCatalog.baselineModels), isTrue);
    });
  });

  // ------------------------------------------------- missing / corrupt provenance
  group('provenance asset unavailable at load time', () {
    tearDown(IqCarsOverlay.debugResetForTest);

    Future<void> loadWith(Future<String> Function(String path) provenance) async {
      IqCarsOverlay.debugResetForTest();
      IqCarsOverlay.debugAssetLoader = (path) async =>
          path == IqCarsOverlay.provenanceAssetPath ? provenance(path) : overlayRaw;
      CarCatalog.applyIqCarsOverlay(await IqCarsOverlay.ensureLoaded());
    }

    void expectSafeFallback() {
      // the overlay itself still works: approved additions are present ...
      expect(IqCarsOverlay.current.modelCount, 1558);
      expect(IqCarsOverlay.current.hasProvenance, isFalse);
      expect(CarCatalog.trimsFor('Ford', 'Everest'),
          ['Limited', 'XLT', 'Mid Range', 'XLS', 'Titanium', 'Trend', 'Ambiente', 'Other']);
      // ... and no option is lost anywhere
      expect(CarCatalog.brands, CarCatalog.baselineBrands);
      expect(CarCatalog.models, CarCatalog.baselineModels);
      for (final be in CarCatalog.baselineTrimsByBrandModel.entries) {
        for (final me in be.value.entries) {
          expect(CarCatalog.trimsFor(be.key, me.key), containsAll(me.value),
              reason: '${be.key} ${me.key}');
        }
      }
      // engines / cylinders do not depend on the provenance asset
      final iq = parseCarSpecDatasetJsonString(specRaw).index!
        ..attachIqCarsOverlay(IqCarsOverlay.current);
      expect(sellEngines(iq, 'Ford', 'Everest').take(7),
          ['2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 TD']);
    }

    test('missing asset: overlay loads, order unchanged, nothing lost', () async {
      await loadWith((p) async => throw StateError('Unable to load asset: $p'));
      expectSafeFallback();
    });

    test('malformed asset: overlay loads, order unchanged, nothing lost', () async {
      await loadWith((_) async => '{"_meta": {"kind": "iqcars_provenance"}, "Toyota": ');
      expectSafeFallback();
    });

    test('wrong-kind asset: ignored', () async {
      await loadWith((_) async => overlayRaw);
      expectSafeFallback();
    });

    test('a valid asset restores IQ-first ordering', () async {
      await loadWith((_) async => provenanceRaw);
      expect(IqCarsOverlay.current.hasProvenance, isTrue);
      expect(CarCatalog.trimsFor('Ford', 'Everest').take(3), ['Limited', 'XLT', 'XLS']);
    });
  });

  // -------------------------------------------------------------------- trims
  group('trims', () {
    List<String> base(String b, String m) =>
        CarCatalog.baselineTrimsByBrandModel[b]![m]!;

    test('Ford Everest: IQ (shared + approved) first, CarNet-only after, Other last', () {
      expect(base('Ford', 'Everest'), ['Limited', 'XLT', 'Mid Range', 'XLS', 'Other']);
      expect(CarCatalog.trimsFor('Ford', 'Everest'), [
        'Limited', 'XLT', 'XLS', 'Titanium', 'Trend', 'Ambiente', //
        'Mid Range', 'Other',
      ]);
    });

    test('Toyota Corolla: shared trims appear once, in the IQ group', () {
      final t = CarCatalog.trimsFor('Toyota', 'Corolla');
      final adds = overlay.additionsFor('Toyota', 'Corolla')!.trims;
      const shared = ['Base', 'L', 'LE', 'GLI', 'XLI', 'SE', 'Sport', 'XLE', 'XSE', 'S'];
      expect(t.take(shared.length + adds.length), [...shared, ...adds]);
      for (final s in shared) {
        expect(t.where((x) => x == s), hasLength(1), reason: s);
      }
      final carnetOnly = base('Toyota', 'Corolla')
          .where((x) => !shared.contains(x) && x != 'Other')
          .toList();
      expect(t.skip(shared.length + adds.length), [...carnetOnly, 'Other']);
      // Look-alikes stay separate, CarNet-only entries: IQ "Limited" vs CarNet
      // "Limited Special Edition", CarNet "IM", CarNet "Apex" vs IQ "Apex SE".
      expect(CarCatalog.isIqTrim('Toyota', 'Corolla', 'Limited'), isTrue);
      expect(CarCatalog.isIqTrim('Toyota', 'Corolla', 'Limited Special Edition'), isFalse);
      expect(t.indexOf('Limited'), lessThan(t.indexOf('Limited Special Edition')));
      expect(carnetOnly, containsAll(['Limited Special Edition', 'IM', 'Apex', 'GR Corolla']));
    });

    test('Toyota Corolla Cross vs Corolla: independent trim groups', () {
      final t = CarCatalog.trimsFor('Toyota', 'Corolla Cross');
      final adds = overlay.additionsFor('Toyota', 'Corolla Cross')!.trims;
      expect(t, [
        'L', 'LE', 'XLE', ...adds, //
        'GLI', 'Hybrid', 'Elite +', 'Special Edition', 'XL', 'Other',
      ]);
      expect(CarCatalog.isIqTrim('Toyota', 'Corolla Cross', 'Hybrid'), isFalse,
          reason: 'the CarNet "Hybrid" trim is not an IQ trim: it is kept, after IQ');
      expect(CarCatalog.trimsFor('Toyota', 'Corolla').contains('Elite +'), isFalse,
          reason: 'trims never leak between Corolla and Corolla Cross');
    });

    test('Toyota Land Cruiser keeps its CarNet-only trims; Prado is ordered on its own', () {
      final lc = CarCatalog.trimsFor('Toyota', 'Land Cruiser');
      final lcAdds = overlay.additionsFor('Toyota', 'Land Cruiser')!.trims;
      expect(lc.take(2 + lcAdds.length), ['GX', 'VX', ...lcAdds]);
      final lcRest = base('Toyota', 'Land Cruiser')
          .where((t) => t != 'GX' && t != 'VX' && t != 'Other')
          .toList();
      expect(lc.skip(2 + lcAdds.length), [...lcRest, 'Other']);
      // IQ's held dotted lookalikes were never merged with CarNet's names
      for (final carnetOnly in ['GXR', 'VXR', 'EXR', 'VXS']) {
        expect(lc.indexOf(carnetOnly), greaterThanOrEqualTo(2 + lcAdds.length),
            reason: carnetOnly);
      }
      expect(lc, isNot(contains('GX.R')));

      final prado = CarCatalog.trimsFor('Toyota', 'Land Cruiser Prado');
      final pAdds = overlay.additionsFor('Toyota', 'Land Cruiser Prado')!.trims;
      const pShared = ['TX', 'GXR', 'VXL', 'TXL', 'Adventure'];
      expect(prado.take(pShared.length + pAdds.length), [...pShared, ...pAdds]);
      expect(prado.last, 'Other');
    });

    test('every model in the catalog: IQ trims strictly before CarNet-only trims', () {
      var reordered = 0, exercised = 0;
      for (final be in CarCatalog.baselineModels.entries) {
        final b = be.key;
        for (final m in be.value) {
          final baseTrims = CarCatalog.baselineTrimsByBrandModel[b]?[m];
          final got = CarCatalog.trimsByBrandModel[b]?[m] ?? baseTrims;
          if (got == null) continue;
          exercised++;
          final reason = '$b $m';
          expect(got.length, got.toSet().length, reason: '$reason: no duplicates');
          // nothing removed, nothing renamed
          if (baseTrims != null) {
            expect(got, containsAll(baseTrims), reason: reason);
          }
          final adds = overlay.additionsFor(b, m)?.trims ?? const <String>[];
          final extra = got.toSet().difference((baseTrims ?? const <String>[]).toSet());
          expect(extra.every(adds.contains), isTrue, reason: '$reason: only approved additions');
          expect(adds.every(got.contains), isTrue, reason: '$reason: every approved addition present');
          // order: IQ group, CarNet-only group, trailing Other
          final hasOther = got.length > 1 && got.last.toLowerCase() == 'other';
          final body = hasOther ? got.sublist(0, got.length - 1) : got;
          final firstNonIq = body.indexWhere((t) => !CarCatalog.isIqTrim(b, m, t));
          if (firstNonIq >= 0) {
            expect(
              body.skip(firstNonIq).any((t) => CarCatalog.isIqTrim(b, m, t)),
              isFalse,
              reason: '$reason: an IQ trim sits below a CarNet-only trim',
            );
          }
          if (baseTrims != null) {
            // existing relative order is kept inside each group
            final baseOrder = baseTrims.where(got.contains).toList();
            expect(body.where(baseOrder.contains).where((t) => CarCatalog.isIqTrim(b, m, t)).toList(),
                baseOrder.where((t) => CarCatalog.isIqTrim(b, m, t) && t.toLowerCase() != 'other').toList(),
                reason: '$reason: IQ group keeps CarNet order');
            expect(body.where(baseOrder.contains).where((t) => !CarCatalog.isIqTrim(b, m, t)).toList(),
                baseOrder.where((t) => !CarCatalog.isIqTrim(b, m, t) && !(hasOther && t == got.last)).toList(),
                reason: '$reason: CarNet-only group keeps CarNet order');
            if (baseTrims.last.toLowerCase() == 'other' && baseTrims.length > 1) {
              expect(got.last, baseTrims.last, reason: '$reason: Other stays last');
            }
            if (got.join('|') != baseTrims.join('|')) reordered++;
          }
        }
      }
      expect(exercised, greaterThan(700));
      expect(reordered, greaterThan(200), reason: 'the rule is actually exercised');
    });

    test('shared trims are exact name matches, never lookalikes', () {
      // Every trim the provenance calls shared is a CarNet trim of that model
      // (same spelling modulo case / spacing); every approved addition is NOT.
      for (final be in provenanceJson.entries) {
        if (be.key.startsWith('_')) continue;
        for (final me in (be.value as Map).entries) {
          final shared =
              ((me.value as Map)['trims'] as List?)?.cast<String>() ?? const <String>[];
          final carnet = CarCatalog.baselineTrimsByBrandModel[be.key]?[me.key] ??
              const <String>[];
          final carnetKeys = {for (final t in carnet) t.trim().toLowerCase()};
          for (final t in shared) {
            expect(carnetKeys, contains(t.trim().toLowerCase()),
                reason: '${be.key} ${me.key} $t');
          }
          final adds = overlay.additionsFor(be.key, me.key)?.trims ?? const <String>[];
          for (final t in adds) {
            expect(carnetKeys.contains(t.trim().toLowerCase()), isFalse,
                reason: '${be.key} ${me.key}: approved addition $t is already CarNet');
            expect(shared.map((s) => s.toLowerCase()), isNot(contains(t.toLowerCase())));
          }
        }
      }
    });

    test('Search and Sell read the same trim order', () {
      // Search: CarCatalog.trimsByBrandModel[brand][model]; Sell / Edit:
      // CarCatalog.trimsFor(brand, model).
      var compared = 0;
      for (final be in CarCatalog.baselineTrimsByBrandModel.entries) {
        for (final me in be.value.entries) {
          expect(CarCatalog.trimsByBrandModel[be.key]![me.key],
              CarCatalog.trimsFor(be.key, me.key),
              reason: '${be.key} ${me.key}');
          compared++;
        }
      }
      expect(compared, greaterThan(500));
    });

    test('a model with no IQ data keeps its trims exactly (rule 6)', () {
      CarCatalog.applyCatalogFromAsset({
        'trimsByBrandModel': {
          ...(catalogJson['trimsByBrandModel'] as Map).cast<String, dynamic>(),
          'Toyota': {
            ...((catalogJson['trimsByBrandModel'] as Map)['Toyota'] as Map)
                .cast<String, dynamic>(),
            'Concept X': ['Zed', 'Alpha', 'Mid', 'Other'],
          },
        },
      });
      expect(CarCatalog.trimsFor('Toyota', 'Concept X'),
          ['Zed', 'Alpha', 'Mid', 'Other']);
      expect(CarCatalog.trimsFor('Toyota', 'No Such Model'), ['Base']);
      expect(CarCatalog.trimsFor(null, 'Corolla'), ['Base']);
      expect(CarCatalog.trimsFor('Toyota', null), ['Base']);
    });

    test('without provenance the previous additive order is kept', () {
      CarCatalog.applyIqCarsOverlay(overlayNoProvenance);
      expect(CarCatalog.trimsFor('Ford', 'Everest'), [
        'Limited', 'XLT', 'Mid Range', 'XLS', 'Titanium', 'Trend', 'Ambiente', 'Other', //
      ]);
      CarCatalog.applyIqCarsOverlay(IqCarsOverlay.empty);
      expect(CarCatalog.trimsFor('Ford', 'Everest'),
          ['Limited', 'XLT', 'Mid Range', 'XLS', 'Other']);
    });
  });

  // ------------------------------------------------------ engines / cylinders
  group('engine sizes and cylinders', () {
    test('iqFirstOptions: stable, lossless, same instance when nothing to do', () {
      final xs = ['Any', 'c', 'a', 'd', 'b'];
      expect(iqFirstOptions(xs, {'a', 'b'}), ['Any', 'a', 'b', 'c', 'd']);
      expect(iqFirstOptions(xs, {'d', 'c'}), ['Any', 'c', 'd', 'a', 'b']);
      expect(identical(iqFirstOptions(xs, null), xs), isTrue);
      expect(identical(iqFirstOptions(xs, <String>{}), xs), isTrue);
      expect(identical(iqFirstOptions(xs, {'zzz'}), xs), isTrue,
          reason: 'IQ values not in the list change nothing');
      final allIq = ['Any', 'a', 'b'];
      expect(identical(iqFirstOptions(allIq, {'a', 'b'}), allIq), isTrue);
      expect(iqFirstOptions(['b', 'a', 'Any'], {'a'}, passthrough: null),
          ['a', 'b', 'Any']);
      expect(iqFirstOptions(xs, {'b'}).toSet(), xs.toSet());
    });

    test('Ford Everest engines: IQ sizes first, CarNet-only 2.0 D / 3.2 D after', () {
      final o = sellOpts(iqIdx, 'Ford', 'Everest')!;
      final expected = [
        '2.0 TD', '2.2 TD', '2.3 T', '2.5', '2.7 T', '3.0 TD', '3.2 TD', // IQ
        '2.0 D', '3.2 D', // CarNet only
      ];
      expect(sellEngines(iqIdx, 'Ford', 'Everest'), expected);
      expect(search(iqIdx, 'Ford', 'Everest').engineSizes, ['Any', ...expected]);
      expect(o.engineSizes, expected.toSet(), reason: 'nothing added or dropped');
      expect(o.iqEngineSizes, expected.take(7).toSet());
      // without the overlay the plain CarNet order is unchanged
      expect(search(plainIdx, 'Ford', 'Everest').engineSizes,
          ['Any', '2.0 D', '2.0 TD', '3.0 TD', '3.2 D']);
    });

    test('engine identity is displacement + qualifier: 2.4 != 2.4 T != 2.4 D', () {
      final o = IqCarsOverlay.parse(
        '{"_meta":{"kind":"iqcars_overlay"},"Zed":{"Zeta":'
        '{"engine_variants_add":["2.4T","2.0"],"cylinders":[6]}}}',
      );
      expect(
        o.approvedEngineLabels('Zed', 'Zeta', ['2.0 D', '2.4 T', '2.4', '2.0', '2.4 D']),
        {'2.4 T', '2.0'},
      );
      expect(o.approvedEngineLabels('Zed', 'Nope', ['2.0']), isEmpty);
      expect(IqCarsOverlay.empty.approvedEngineLabels('Zed', 'Zeta', ['2.0']), isEmpty);
    });

    test('every model: engines IQ-first, lossless, CarNet order kept inside groups', () {
      var mixed = 0, models = 0;
      for (final be in overlay.entries) {
        for (final m in be.value.keys) {
          final o = sellOpts(iqIdx, be.key, m);
          if (o == null || o.engineSizes.isEmpty) continue;
          models++;
          final reason = '${be.key} $m';
          final ordered = sortCatalogEngineSizeLabels(
            o.engineSizes,
            iqLabels: o.iqEngineSizes,
          );
          final plain = sortCatalogEngineSizeLabels(o.engineSizes);
          expect(ordered.length, ordered.toSet().length, reason: '$reason: once each');
          expect(ordered.toSet(), o.engineSizes, reason: '$reason: lossless');
          expect(o.engineSizes.containsAll(o.iqEngineSizes), isTrue, reason: reason);
          if (o.iqEngineSizes.isEmpty) {
            expect(ordered, plain, reason: '$reason: no IQ data -> existing order');
            continue;
          }
          final (iq, carnet) = split(ordered, o.iqEngineSizes.contains);
          expect(ordered, [...iq, ...carnet], reason: '$reason: IQ above CarNet-only');
          expect(iq, plain.where(o.iqEngineSizes.contains).toList(), reason: reason);
          expect(carnet, plain.where((e) => !o.iqEngineSizes.contains(e)).toList(),
              reason: reason);
          if (iq.isNotEmpty && carnet.isNotEmpty) mixed++;
        }
      }
      expect(models, greaterThan(1000));
      expect(mixed, greaterThan(20), reason: 'models with both groups exist');
    });

    test('every model: cylinders IQ-first, nothing lost, Search == Sell order', () {
      var mixed = 0;
      for (final be in overlay.entries) {
        for (final m in be.value.keys) {
          final o = sellOpts(iqIdx, be.key, m);
          final reason = '${be.key} $m';
          final sell = sellCylinders(iqIdx, be.key, m);
          final legacy = narrowOptionsToCatalog(sellCylinderDefaults, o?.cylinderCounts);
          final iq = o?.iqCylinderCounts ?? const <String>{};
          // membership is decided exactly as before; only IQ extras may join
          if (!identical(legacy, sellCylinderDefaults)) {
            expect(sell.toSet().containsAll(legacy), isTrue, reason: reason);
            expect(sell.toSet().difference(legacy.toSet()).every(iq.contains),
                isTrue,
                reason: reason);
          }
          expect(sell.length, sell.toSet().length, reason: reason);
          if (iq.isNotEmpty && !identical(sell, sellCylinderDefaults)) {
            final (a, b) = split(sell, iq.contains);
            expect(sell, [...a, ...b], reason: '$reason: IQ above CarNet-only');
            if (a.isNotEmpty && b.isNotEmpty) mixed++;
          }
          // Search shows the same relative order for the counts both offer
          final searchList = search(iqIdx, be.key, m)
              .cylinderCounts
              .where((c) => c != 'Any')
              .toList();
          final common = sell.toSet().intersection(searchList.toSet());
          expect(searchList.where(common.contains).toList(),
              sell.where(common.contains).toList(),
              reason: '$reason: Search and Sell order cylinders identically');
        }
      }
      expect(mixed, greaterThan(10), reason: 'models with both groups exist');
    });

    test('Search and Sell list engines identically for the representative models', () {
      for (final (b, m) in representative) {
        final sell = sellEngines(iqIdx, b, m);
        final s = search(iqIdx, b, m).engineSizes;
        if (sell.isEmpty) {
          expect(s, ['Any', 'generic-engine-ladder'], reason: '$b $m');
        } else {
          expect(s, ['Any', ...sell], reason: '$b $m');
        }
      }
    });

    test('representative models: IQ engines above CarNet-only, all retained', () {
      for (final (b, m) in representative) {
        final o = sellOpts(iqIdx, b, m);
        final p = sellOpts(plainIdx, b, m);
        if (o == null) continue;
        final ordered = sellEngines(iqIdx, b, m);
        // every CarNet engine of the plain index is still offered
        expect(ordered.toSet().containsAll(p?.engineSizes ?? const <String>{}), isTrue,
            reason: '$b $m');
        final firstNon = ordered.indexWhere((e) => !o.iqEngineSizes.contains(e));
        if (firstNon >= 0) {
          expect(ordered.skip(firstNon).any(o.iqEngineSizes.contains), isFalse,
              reason: '$b $m');
        }
      }
    });

    test('a matched model with no IQ engine data keeps its existing engine order', () {
      var checked = 0;
      for (final be in provenanceJson.entries) {
        if (be.key.startsWith('_')) continue;
        for (final m in (be.value as Map).keys.cast<String>()) {
          if (overlay.additionsFor(be.key, m) != null) continue;
          final o = sellOpts(iqIdx, be.key, m);
          if (o == null || o.engineSizes.isEmpty) continue;
          expect(o.iqEngineSizes, isEmpty, reason: '${be.key} $m');
          expect(sellEngines(iqIdx, be.key, m), sortCatalogEngineSizeLabels(o.engineSizes),
              reason: '${be.key} $m');
          expect(sellEngines(iqIdx, be.key, m), sellEngines(plainIdx, be.key, m),
              reason: '${be.key} $m: same as without IQ Cars');
          checked++;
        }
      }
      expect(checked, greaterThan(3));
      // an unknown model: nothing to order
      expect(sellEngines(iqIdx, 'Zeta Motors', 'Z1'), isEmpty);
    });

    test('Hybrid / Plug-in Hybrid and the other spec fields are not reordered', () {
      var withHybrid = 0;
      for (final (b, m) in representative) {
        final a = plainIdx.homeFilterFieldOptions(b, m, '');
        final c = iqIdx.homeFilterFieldOptions(b, m, '');
        const none = <String>{};
        expect(c?.fuelTypes ?? none, a?.fuelTypes ?? none, reason: '$b $m fuel');
        expect(c?.transmissions ?? none, a?.transmissions ?? none, reason: '$b $m transmission');
        expect(c?.bodyTypes ?? none, a?.bodyTypes ?? none, reason: '$b $m body');
        expect(c?.driveTypes ?? none, a?.driveTypes ?? none, reason: '$b $m drive');
        expect(c?.seatings ?? none, a?.seatings ?? none, reason: '$b $m seating');
        // The Search lists for these fields come out in the very same order
        // with and without IQ Cars (IQ publishes no provenance for them).
        final sp = search(plainIdx, b, m);
        final si = search(iqIdx, b, m);
        expect(si.fuelTypes, sp.fuelTypes, reason: '$b $m');
        expect(si.transmissions, sp.transmissions, reason: '$b $m');
        expect(si.bodyTypes, sp.bodyTypes, reason: '$b $m');
        expect(si.driveTypes, sp.driveTypes, reason: '$b $m');
        expect(si.seatings, sp.seatings, reason: '$b $m');
        if (c != null && c.fuelTypes.any((f) => f.toLowerCase().contains('hybrid'))) {
          withHybrid++;
        }
      }
      expect(withHybrid, greaterThan(0), reason: 'a Hybrid-capable model was exercised');
    });
  });

  // ------------------------------------------------------ saved / filtered values
  group('selecting an option keeps the canonical value', () {
    test('Sell payload stores the exact brand / model / trim / engine / cylinders', () {
      for (final c in const [
        // IQ-first and CarNet-only picks, side by side
        ('Ford', 'Everest', 'Titanium', '2.2 TD', '5'),
        ('Ford', 'Everest', 'Mid Range', '2.0 D', '4'),
        ('Toyota', 'Corolla', 'Limited', '1.8', '4'),
        ('Toyota', 'Corolla', 'Limited Special Edition', '1.8', '4'),
        ('Toyota', 'Corolla Cross', 'Hybrid', '2.0', '4'),
        ('Toyota', 'Land Cruiser', 'GXR', '4.0', '6'),
        ('Toyota', 'Land Cruiser', 'GX.R Limited', '4.5 TD', '8'),
      ]) {
        final payload = buildSellCarCreatePayload({
          'brand': c.$1,
          'model': c.$2,
          'trim': c.$3,
          'year': '2020',
          'engine_size': c.$4,
          'cylinder_count': c.$5,
        });
        expect(payload['brand'], c.$1);
        expect(payload['model'], c.$2);
        expect(payload['trim'], c.$3);
        expect(payload['engine_size'], double.parse(c.$4.split(' ').first), reason: '$c');
        expect(payload['cylinder_count'], int.parse(c.$5));
        final update = buildSellCarUpdatePayload({
          'brand': c.$1,
          'model': c.$2,
          'trim': c.$3,
          'year': '2020',
          'engine_size': c.$4,
          'cylinder_count': c.$5,
        });
        expect(update['brand'], c.$1);
        expect(update['model'], c.$2);
        expect(update['trim'], c.$3);
        expect(update['engine_size'], payload['engine_size']);
      }
    });

    test('Edit Listing restores a saved listing unchanged, whichever group its trim is in', () {
      for (final trim in ['Titanium', 'Mid Range', 'Limited']) {
        final draft = listingToSellDraftSnapshot({
          'id': 77,
          'brand': 'Ford',
          'model': 'Everest',
          'trim': trim,
          'year': 2020,
          'engine_size': 2.2,
          'cylinder_count': 5,
        });
        final car = Map<String, dynamic>.from(draft['carData'] as Map);
        expect(car['brand'], 'Ford');
        expect(car['model'], 'Everest');
        expect(car['trim'], trim);
        // the saved trim is a member of the ordered picker list: it stays selectable
        expect(CarCatalog.trimsFor('Ford', 'Everest'), contains(car['trim']));
      }
    });

    test('Search sends exactly the picked value; the model filter stays exact', () {
      for (final (b, m) in representative) {
        final trims = CarCatalog.trimsByBrandModel[b]?[m] ?? const <String>[];
        final iqTrim = trims.firstWhere((t) => CarCatalog.isIqTrim(b, m, t), orElse: () => '');
        final carnetTrim = trims.firstWhere(
          (t) => t.toLowerCase() != 'other' && !CarCatalog.isIqTrim(b, m, t),
          orElse: () => '',
        );
        for (final t in [iqTrim, carnetTrim].where((t) => t.isNotEmpty)) {
          final f = HomeFiltersSnapshot(brand: b, model: m, trim: t);
          final q = homeFiltersToApiQuery(f);
          expect(q['brand'], b);
          expect(q['model'], m);
          expect(q['model_match'], 'exact');
          expect(q['trim'], t);
          final rows = <Map<String, dynamic>>[
            {'brand': b, 'model': m, 'trim': t},
            {'brand': b, 'model': '$m Other', 'trim': t},
            {'brand': 'Zeta Motors', 'model': m, 'trim': t},
          ];
          expect(filterListingsByHomeFilters(rows, f), [rows.first], reason: '$b $m $t');
        }
      }
    });

    test('Corolla never matches Corolla Cross, Land Cruiser never matches Prado', () {
      final rows = <Map<String, dynamic>>[
        {'brand': 'Toyota', 'model': 'Corolla', 'trim': 'LE'},
        {'brand': 'Toyota', 'model': 'Corolla Cross', 'trim': 'LE'},
        {'brand': 'Toyota', 'model': 'Land Cruiser', 'trim': 'GX'},
        {'brand': 'Toyota', 'model': 'Land Cruiser Prado', 'trim': 'GX'},
      ];
      List<String> ids(String model) => filterListingsByHomeFilters(
            rows,
            HomeFiltersSnapshot(brand: 'Toyota', model: model),
          ).map((r) => r['model'] as String).toList();
      expect(ids('Corolla'), ['Corolla']);
      expect(ids('Corolla Cross'), ['Corolla Cross']);
      expect(ids('Land Cruiser'), ['Land Cruiser']);
      expect(ids('Land Cruiser Prado'), ['Land Cruiser Prado']);
    });

    test('engine size and cylinder picks go to the API and the filter unchanged', () {
      for (final (b, m) in representative) {
        final engines = sellEngines(iqIdx, b, m);
        final cyls = sellCylinders(iqIdx, b, m);
        for (final e in engines) {
          final q = homeFiltersToApiQuery(
            HomeFiltersSnapshot(brand: b, model: m, engineSize: e),
          );
          expect(q['engine_size'], e, reason: '$b $m $e');
        }
        for (final c in cyls) {
          final q = homeFiltersToApiQuery(
            HomeFiltersSnapshot(brand: b, model: m, cylinderCount: c),
          );
          expect(q['cylinder_count'], c, reason: '$b $m $c');
        }
      }
      // plain numeric picks also filter the listings themselves
      final rows = <Map<String, dynamic>>[
        {'brand': 'Ford', 'model': 'Everest', 'engine_size': 2.5, 'cylinder_count': 5},
        {'brand': 'Ford', 'model': 'Everest', 'engine_size': 3.0, 'cylinder_count': 6},
      ];
      expect(
        filterListingsByHomeFilters(
          rows,
          const HomeFiltersSnapshot(brand: 'Ford', model: 'Everest', engineSize: '2.5'),
        ),
        [rows.first],
      );
      expect(
        filterListingsByHomeFilters(
          rows,
          const HomeFiltersSnapshot(brand: 'Ford', model: 'Everest', cylinderCount: '6'),
        ),
        [rows.last],
      );
    });
  });

  // -------------------------------------------------------- English / Arabic / Kurdish
  group('English, Arabic and Kurdish', () {
    const names = <String, Map<String, String>>{
      'ar': {
        'toyota': 'تويوتا',
        'toyota|corolla': 'كورولا',
        'toyota|corolla cross': 'كورولا كروس',
        'toyota|land cruiser': 'لاند كروزر',
        'toyota|land cruiser prado': 'لاند كروزر برادو',
      },
      'ku': {
        'toyota': 'تۆیۆتا',
        'toyota|corolla': 'کۆرۆلا',
        'toyota|corolla cross': 'کۆرۆلا کرۆس',
        'toyota|land cruiser': 'لاند کرۆزەر',
        'toyota|land cruiser prado': 'لاند کرۆزەر پرادۆ',
      },
    };

    List<String> display(String locale, String brand, List<String> models) {
      if (locale == 'en') return models;
      return [
        for (final m in models)
          CarNameTranslations.getLocalizedModelForLocale(locale, brand, m),
      ];
    }

    for (final locale in const ['en', 'ar', 'ku']) {
      test('$locale: canonical order is language independent and values round-trip', () {
        if (locale != 'en') {
          CarNameTranslations.debugInstallPack(
            locale,
            brands: {'toyota': names[locale]!['toyota']!},
            models: {
              for (final e in names[locale]!.entries)
                if (e.key.contains('|')) e.key: e.value,
            },
          );
        }
        final models = CarCatalog.models['Toyota']!;
        final shown = display(locale, 'Toyota', models);
        expect(shown.length, models.length);
        // display <-> canonical is a bijection on the translated entries: picking
        // the label gives back the exact canonical value that gets saved
        final back = <String, String>{};
        for (var i = 0; i < models.length; i++) {
          back.putIfAbsent(shown[i], () => models[i]);
        }
        for (final m in ['Corolla', 'Corolla Cross', 'Land Cruiser', 'Land Cruiser Prado']) {
          final label = display(locale, 'Toyota', [m]).single;
          expect(back[label], m, reason: '$locale $m');
        }
        // order of the canonical values does not depend on the UI language
        expect(models, CarCatalog.models['Toyota']);
        // trims and spec lists are canonical strings: identical in every language
        expect(CarCatalog.trimsFor('Toyota', 'Corolla Cross').take(3), ['L', 'LE', 'XLE']);
        expect(sellEngines(iqIdx, 'Ford', 'Everest').first, '2.0 TD');
        expect(search(iqIdx, 'Ford', 'Everest').engineSizes.take(3),
            ['Any', '2.0 TD', '2.2 TD']);
      });
    }

    test('Arabic and Kurdish labels exist for the representative Toyota models', () {
      for (final locale in const ['ar', 'ku']) {
        CarNameTranslations.debugInstallPack(
          locale,
          brands: {'toyota': names[locale]!['toyota']!},
          models: {
            for (final e in names[locale]!.entries)
              if (e.key.contains('|')) e.key: e.value,
          },
        );
        for (final m in ['Corolla', 'Corolla Cross', 'Land Cruiser']) {
          expect(
            CarNameTranslations.getLocalizedModelForLocale(locale, 'Toyota', m),
            isNot(m),
            reason: '$locale $m',
          );
        }
      }
    });
  });

  // ------------------------------------------------------------- report helper
  test('prints the representative orderings (informational)', () {
    for (final (b, m) in representative) {
      final trims = CarCatalog.trimsFor(b, m);
      final iqTrims = trims.where((t) => CarCatalog.isIqTrim(b, m, t)).length;
      // ignore: avoid_print
      print('$b $m: trims=${trims.length} (IQ first: $iqTrims) '
          'engines=${sellEngines(iqIdx, b, m)} cylinders=${sellCylinders(iqIdx, b, m)}');
    }
  });
}
