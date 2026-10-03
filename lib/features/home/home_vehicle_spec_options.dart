import '../../services/car_spec_index.dart';
import 'home_multi_select_filter.dart';

/// Catalog-dependent vehicle fields in Search/Filters. These are exactly the
/// fields Sell step 2 narrows from the spec catalog
/// (`CarSpecIndex.sellFieldOptionsUnion` -> [CatalogSellFieldOptions]).
enum HomeVehicleField {
  bodyType,
  transmission,
  fuelType,
  driveType,
  cylinderCount,
  seating,
  engineSize,
}

/// Search's vehicle selection context. Search resolves options with the same
/// catalog resolver as Sell; the only difference is Search has an optional
/// model-year *window* instead of one concrete year.
class HomeVehicleContext {
  const HomeVehicleContext({
    this.brand,
    this.model,
    this.trim,
    this.minYear,
    this.maxYear,
  });

  final String? brand;
  final String? model;
  final String? trim;
  final int? minYear;
  final int? maxYear;

  /// Cache key for the model-level resolution (trim is NOT an input).
  String get modelCacheKey =>
      '${brand ?? ''}\x1e${model ?? ''}\x1e${minYear ?? ''}\x1e${maxYear ?? ''}';

  /// Cache key for the trim-aware engine-size resolution.
  String get engineCacheKey => '$modelCacheKey\x1e${trim ?? ''}';
}

CatalogSellFieldOptions? _resolve(
  CarSpecIndex? idx,
  HomeVehicleContext ctx,
  String trim,
) {
  final brand = ctx.brand?.trim() ?? '';
  final model = ctx.model?.trim() ?? '';
  if (idx == null || brand.isEmpty || model.isEmpty) return null;
  return idx.homeFilterFieldOptions(
    brand,
    model,
    trim.isEmpty ? CarSpecIndex.catalogAutofillModelOnly : trim,
    rangeMinYear: ctx.minYear,
    rangeMaxYear: ctx.maxYear,
  );
}

/// Model-level catalog resolution — **make + model + year window**, trim is
/// deliberately ignored. This is Sell step 2's dependency depth
/// (`catalogAutofillModelOnly`), used for cylinders, body type, transmission,
/// fuel type, drive type and seating.
///
/// Returns null ("catalog cannot answer") when no index is loaded, no model is
/// selected, the model is unknown to the catalog, or the year window excludes
/// every catalog year. Individual fields inside a non-null result can still be
/// empty sets (catalog knows the model but not that field).
CatalogSellFieldOptions? resolveHomeVehicleCatalogOptions(
  CarSpecIndex? idx,
  HomeVehicleContext ctx,
) =>
    _resolve(idx, ctx, CarSpecIndex.catalogAutofillModelOnly);

/// Trim-aware resolution — **make + model + trim + year window**. Used ONLY for
/// engine size: Search has always narrowed engine sizes by the selected trim
/// (pre-existing, Search-only behavior; Sell step 2 does not). With no trim
/// selected this equals [resolveHomeVehicleCatalogOptions].
CatalogSellFieldOptions? resolveHomeVehicleEngineCatalogOptions(
  CarSpecIndex? idx,
  HomeVehicleContext ctx,
) =>
    _resolve(idx, ctx, ctx.trim?.trim() ?? '');

/// Default/global option lists for every catalog-dependent Search field (the
/// lists Search shows when the catalog has nothing to say).
class HomeVehicleFieldDefaults {
  const HomeVehicleFieldDefaults({
    required this.bodyTypes,
    required this.transmissions,
    required this.fuelTypes,
    required this.driveTypes,
    required this.cylinderCounts,
    required this.seatings,
    this.engineSizes = const <String>[],
    this.engineSizesProvider,
  });

  final List<String> bodyTypes;
  final List<String> transmissions;
  final List<String> fuelTypes;
  final List<String> driveTypes;
  final List<String> cylinderCounts;
  final List<String> seatings;

  /// Eager default engine sizes. Ignored when [engineSizesProvider] is set.
  final List<String> engineSizes;

  /// Lazy default engine sizes. Building the full-catalog engine list scans
  /// every spec row, so callers pass a provider and only pay for it when the
  /// catalog has nothing to say about the selected vehicle's engines.
  final List<String> Function()? engineSizesProvider;

  List<String> get resolvedEngineSizes =>
      engineSizesProvider?.call() ?? engineSizes;
}

/// Allowed values per dependent field after applying the shared fallback
/// contract (see [narrowOptionsToCatalog]) independently for **each** field.
class HomeVehicleFieldOptions {
  const HomeVehicleFieldOptions._({
    required this.bodyTypes,
    required this.transmissions,
    required this.fuelTypes,
    required this.driveTypes,
    required this.cylinderCounts,
    required this.seatings,
    required this.engineSizes,
    required this.narrowedFields,
  });

  /// [catalog] null (or a field missing from it) -> that field's [defaults].
  ///
  /// [catalog] (model-level) drives every field except engine size.
  /// [engineCatalog] (trim-aware) drives engine size only. Pass the same object
  /// as [catalog] when no trim-specific resolution applies; null means "catalog
  /// has nothing for engine size" (defaults), never "reuse [catalog]".
  factory HomeVehicleFieldOptions.resolve({
    required CatalogSellFieldOptions? catalog,
    required CatalogSellFieldOptions? engineCatalog,
    required HomeVehicleFieldDefaults defaults,
  }) {
    final engineSource = engineCatalog;
    final narrowed = <HomeVehicleField>{};

    // `narrowOptionsToCatalog` returns the very same [defaults] instance when it
    // falls back, so identity tells us whether the catalog narrowed the field.
    List<String> pick(
      HomeVehicleField field,
      List<String> base,
      Set<String>? known,
    ) {
      final out = narrowOptionsToCatalog(base, known);
      if (!identical(out, base)) narrowed.add(field);
      return out;
    }

    List<String> engines() {
      final known = engineSource?.engineSizes;
      if (known == null || known.isEmpty) return defaults.resolvedEngineSizes;
      narrowed.add(HomeVehicleField.engineSize);
      return <String>['Any', ...sortCatalogEngineSizeLabels(known)];
    }

    return HomeVehicleFieldOptions._(
      bodyTypes: pick(
        HomeVehicleField.bodyType,
        defaults.bodyTypes,
        catalog?.bodyTypes,
      ),
      transmissions: pick(
        HomeVehicleField.transmission,
        defaults.transmissions,
        catalog?.transmissions,
      ),
      fuelTypes: pick(
        HomeVehicleField.fuelType,
        defaults.fuelTypes,
        catalog?.fuelTypes,
      ),
      driveTypes: pick(
        HomeVehicleField.driveType,
        defaults.driveTypes,
        catalog?.driveTypes,
      ),
      cylinderCounts: pick(
        HomeVehicleField.cylinderCount,
        defaults.cylinderCounts,
        catalog?.cylinderCounts,
      ),
      seatings: pick(
        HomeVehicleField.seating,
        defaults.seatings,
        catalog?.seatings,
      ),
      engineSizes: engines(),
      narrowedFields: Set<HomeVehicleField>.unmodifiable(narrowed),
    );
  }

  final List<String> bodyTypes;
  final List<String> transmissions;
  final List<String> fuelTypes;
  final List<String> driveTypes;
  final List<String> cylinderCounts;
  final List<String> seatings;
  final List<String> engineSizes;

  /// Fields whose list was actually narrowed by the catalog. Only these fields
  /// can hold stale selections; the rest show their defaults and are never
  /// touched by selection cleanup.
  final Set<HomeVehicleField> narrowedFields;
}

/// Current values of every catalog-dependent Search filter.
class HomeVehicleDependentSelections {
  const HomeVehicleDependentSelections({
    this.bodyType,
    this.transmission,
    this.fuelType,
    this.driveType,
    this.cylinderCount,
    this.seating,
    this.engineSize,
  });

  /// Comma-encoded multi-select (see [homeFilterEncodeList]).
  final String? bodyType;
  final String? transmission;

  /// Comma-encoded multi-select.
  final String? fuelType;

  /// Comma-encoded multi-select.
  final String? driveType;
  final String? cylinderCount;
  final String? seating;
  final String? engineSize;

  HomeVehicleDependentSelections copyWith({
    Object? bodyType = _unset,
    Object? transmission = _unset,
    Object? fuelType = _unset,
    Object? driveType = _unset,
    Object? cylinderCount = _unset,
    Object? seating = _unset,
    Object? engineSize = _unset,
  }) {
    return HomeVehicleDependentSelections(
      bodyType: identical(bodyType, _unset) ? this.bodyType : bodyType as String?,
      transmission: identical(transmission, _unset)
          ? this.transmission
          : transmission as String?,
      fuelType: identical(fuelType, _unset) ? this.fuelType : fuelType as String?,
      driveType:
          identical(driveType, _unset) ? this.driveType : driveType as String?,
      cylinderCount: identical(cylinderCount, _unset)
          ? this.cylinderCount
          : cylinderCount as String?,
      seating: identical(seating, _unset) ? this.seating : seating as String?,
      engineSize: identical(engineSize, _unset)
          ? this.engineSize
          : engineSize as String?,
    );
  }

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is HomeVehicleDependentSelections &&
      other.bodyType == bodyType &&
      other.transmission == transmission &&
      other.fuelType == fuelType &&
      other.driveType == driveType &&
      other.cylinderCount == cylinderCount &&
      other.seating == seating &&
      other.engineSize == engineSize;

  @override
  int get hashCode => Object.hash(
        bodyType,
        transmission,
        fuelType,
        driveType,
        cylinderCount,
        seating,
        engineSize,
      );

  @override
  String toString() =>
      'HomeVehicleDependentSelections(body: $bodyType, transmission: '
      '$transmission, fuel: $fuelType, drive: $driveType, cylinders: '
      '$cylinderCount, seating: $seating, engine: $engineSize)';
}

bool _isUnsetFilterValue(String? v) {
  if (v == null) return true;
  final t = v.trim();
  return t.isEmpty || t.toLowerCase() == 'any';
}

bool _containsIgnoreCase(List<String> available, String value) {
  final needle = value.trim().toLowerCase();
  for (final o in available) {
    if (o != 'Any' && o.trim().toLowerCase() == needle) return true;
  }
  return false;
}

String? _keepSingle(String? value, List<String> available) {
  if (_isUnsetFilterValue(value)) return value;
  return _containsIgnoreCase(available, value!) ? value : null;
}

String? _keepMulti(String? raw, List<String> available) {
  final decoded = homeFilterDecodeList(raw);
  if (decoded.isEmpty) return raw;
  final kept =
      decoded.where((v) => _containsIgnoreCase(available, v)).toList();
  if (kept.length == decoded.length) return raw; // untouched: keep exact text
  return homeFilterEncodeList(kept);
}

/// Drops only the selections the catalog has ruled out for the current vehicle.
///
/// Applied independently per field and only to fields the catalog actually
/// narrowed ([HomeVehicleFieldOptions.narrowedFields]): fields without catalog
/// data keep whatever the user chose. Multi-select fields (body / fuel / drive)
/// drop just the invalid entries. A manually typed engine size
/// ([pruneEngineSize] false) is free text and is never pruned.
HomeVehicleDependentSelections sanitizeHomeVehicleDependentSelections(
  HomeVehicleDependentSelections s,
  HomeVehicleFieldOptions options, {
  bool pruneEngineSize = true,
}) {
  final n = options.narrowedFields;
  return HomeVehicleDependentSelections(
    bodyType: n.contains(HomeVehicleField.bodyType)
        ? _keepMulti(s.bodyType, options.bodyTypes)
        : s.bodyType,
    transmission: n.contains(HomeVehicleField.transmission)
        ? _keepSingle(s.transmission, options.transmissions)
        : s.transmission,
    fuelType: n.contains(HomeVehicleField.fuelType)
        ? _keepMulti(s.fuelType, options.fuelTypes)
        : s.fuelType,
    driveType: n.contains(HomeVehicleField.driveType)
        ? _keepMulti(s.driveType, options.driveTypes)
        : s.driveType,
    cylinderCount: n.contains(HomeVehicleField.cylinderCount)
        ? _keepSingle(s.cylinderCount, options.cylinderCounts)
        : s.cylinderCount,
    seating: n.contains(HomeVehicleField.seating)
        ? _keepSingle(s.seating, options.seatings)
        : s.seating,
    engineSize: pruneEngineSize && n.contains(HomeVehicleField.engineSize)
        ? _keepSingle(s.engineSize, options.engineSizes)
        : s.engineSize,
  );
}
