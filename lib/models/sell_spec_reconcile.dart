import 'online_spec_variant.dart';

/// The three linked Sell spec fields that are kept mutually compatible.
enum SellSpecField { engine, cylinders, fuel }

/// A (partial) Sell selection: exact engine label (`3.0`, `3.0 D`, `3.0 T`, ...),
/// cylinder count and a normalised fuel key (`diesel`, `gasoline`, ...).
class SellSpecSelection {
  const SellSpecSelection({this.engine, this.cylinders, this.fuel});

  final String? engine;
  final int? cylinders;
  final String? fuel;

  SellSpecSelection copyWith({String? engine, int? cylinders, String? fuel}) =>
      SellSpecSelection(
        engine: engine ?? this.engine,
        cylinders: cylinders ?? this.cylinders,
        fuel: fuel ?? this.fuel,
      );

  @override
  bool operator ==(Object other) =>
      other is SellSpecSelection &&
      other.engine == engine &&
      other.cylinders == cylinders &&
      other.fuel == fuel;

  @override
  int get hashCode => Object.hash(engine, cylinders, fuel);

  @override
  String toString() => 'SellSpecSelection($engine, $cylinders, $fuel)';
}

/// ONE central compatibility resolver for engine / cylinders / fuel, shared by
/// Sell (listing data) and Search (`search_spec_reconcile.dart` adds only the
/// Search-specific `Any` / multi-fuel semantics on top of it).
///
/// Relationships come ONLY from [rows]: the CarNet spec rows already scoped to
/// the selected Brand + Model + Year (+ trim scope). The approved IQ model-level
/// engine / cylinder lists are independent: they only widen [availableEngines];
/// they never create a combination. An IQ-only engine (no exact CarNet row,
/// e.g. `3.0 T`) gets
///
///  * a cylinder count only when its whole same-displacement CarNet family
///    agrees on one count, and
///  * a fuel only when that family agrees on one fuel AND the engine's own
///    qualifier does not contradict it (a `D` label is a diesel label).
///
/// Conflicting or missing evidence resolves to "unknown": the dependent field is
/// left unchanged. [reconcile] is a pure, single pass: the field the user just
/// changed is never altered and nothing re-triggers it, so there are no loops.
class SellSpecReconciler {
  SellSpecReconciler({
    required Iterable<OnlineSpecVariant> rows,
    required Iterable<String> availableEngines,
    required String? Function(OnlineSpecVariant row) fuelKeyOf,
  })  : _rows = rows.toList(growable: false),
        _engines = availableEngines
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e.toLowerCase() != 'any')
            .toList(growable: false),
        _fuelKeyOf = fuelKeyOf;

  final List<OnlineSpecVariant> _rows;
  final List<String> _engines;
  final String? Function(OnlineSpecVariant row) _fuelKeyOf;

  static const double _litreTol = 0.06;

  /// Every normalised fuel key the [rows] establish.
  ///
  /// CarNet labels plug-in hybrids "Electric" (BMW X5 40e: 1997 cc, 4 cyl; the
  /// dataset's only fuel values are Petrol / Diesel / Electric). A row that
  /// reports "electric" together with a combustion displacement is not a pure
  /// electric: it contributes electric AND gasoline AND hybrid, so it can never
  /// prove a single fuel (no unanimous "Electric"). The fuel taxonomy itself is
  /// untouched. Shared by the resolver and Sell's row-fill so both agree.
  static Set<String> fuelKeysOfRows(
    Iterable<OnlineSpecVariant> rows,
    String? Function(OnlineSpecVariant row) fuelKeyOf,
  ) {
    final out = <String>{};
    for (final r in rows) {
      final k = fuelKeyOf(r) ?? '';
      if (k.isEmpty) continue;
      out.add(k);
      if (k == 'electric' && (r.engineSizeLiters ?? 0) > 0.001) {
        out.addAll(const ['gasoline', 'hybrid']);
      }
    }
    return out;
  }

  static bool _labelIsDiesel(String engine) {
    final i = engine.indexOf(' ');
    return i >= 0 && engine.substring(i).toUpperCase().contains('D');
  }

  static String _suffixOf(String engine) {
    final i = engine.indexOf(' ');
    return i < 0 ? '' : engine.substring(i).trim().toUpperCase();
  }

  bool _sameDisplacement(OnlineSpecVariant r, double lit) {
    final l = r.engineSizeLiters;
    return l != null && (l - lit).abs() < _litreTol;
  }

  /// Trusted cylinder count of an engine label, or null (see
  /// [OnlineSpecVariant.trustedCylinderForEngine]).
  int? cylindersFor(String engine) =>
      OnlineSpecVariant.trustedCylinderForEngine(_rows, engine);

  /// Every fuel key the scoped rows establish for an engine label.
  ///
  /// Exact rows of that label: all their fuels (a label can legitimately exist
  /// in several fuels). An IQ-only label (no exact row): only a fuel the WHOLE
  /// same-displacement family agrees on, and only when the label's own
  /// qualifier does not contradict it (a `D` label is a diesel label). Empty =
  /// unknown; nothing is inferred from a different fuel.
  Set<String> fuelsOf(String engine) {
    final label = engine.trim();
    final lit = OnlineSpecVariant.parseLeadingEngineLiters(label);
    if (label.isEmpty || lit == null || lit <= 0.001) return const {};

    Set<String> keys(Iterable<OnlineSpecVariant> rs) =>
        fuelKeysOfRows(rs, _fuelKeyOf);

    final exact =
        _rows.where((r) => OnlineSpecVariant.engineLabelOf(r) == label);
    if (exact.isNotEmpty) return keys(exact);

    final family = keys(_rows.where((r) => _sameDisplacement(r, lit)));
    if (family.length != 1) return const {};
    if (_labelIsDiesel(label) != (family.first == 'diesel')) return const {};
    return family;
  }

  /// The single trusted fuel key of an engine label, or null when unknown or
  /// ambiguous.
  String? fuelFor(String engine) {
    final s = fuelsOf(engine);
    return s.length == 1 ? s.first : null;
  }

  /// Whether [engine] can exist with [fuel] according to the scoped rows
  /// (unknown evidence is compatible unless the engine's own qualifier vetoes).
  bool fuelCompatible(String engine, String fuel) =>
      _fuelCompatible(engine, fuel);

  /// An engine is compatible with a fuel unless the evidence says otherwise.
  bool _fuelCompatible(String engine, String fuel) {
    final s = fuelsOf(engine);
    if (s.isNotEmpty) return s.contains(fuel);
    // No trusted fuel: only the engine's own diesel qualifier can veto.
    return !(_labelIsDiesel(engine) && fuel != 'diesel');
  }

  bool _hasExactRow(String engine, int cylinders) {
    final lit = OnlineSpecVariant.parseLeadingEngineLiters(engine);
    if (lit == null) return false;
    return _rows.any(
      (r) => _sameDisplacement(r, lit) && r.cylinderCount == cylinders,
    );
  }

  /// Deterministic choice among [candidates] (all already trusted for the field
  /// the user changed). Ordering: keeps the other current values first (the
  /// cylinder count, then the fuel), then
  /// engines whose displacement family has an exact row for the cylinder count,
  /// then the catalog / display order of [_engines]. Finally a richer approved
  /// label (`4.4 T`) replaces its plainer equivalent (`4.4`) only when both have
  /// the same rank and the richer one keeps every qualifier of the plainer one.
  String _pick(
    List<String> candidates, {
    String? preferFuel,
    int? preferCylinders,
  }) {
    int fuelRank(String e) {
      if (preferFuel == null) return 0;
      final s = fuelsOf(e);
      if (s.isEmpty) return _fuelCompatible(e, preferFuel) ? 1 : 2;
      if (!s.contains(preferFuel)) return 2;
      return s.length == 1 ? 0 : 1;
    }

    int cylRank(String e) {
      if (preferCylinders == null) return 0;
      final c = cylindersFor(e);
      if (c == null) return 1;
      return c == preferCylinders ? 0 : 2;
    }

    int exactRank(String e) {
      final c = cylindersFor(e) ?? preferCylinders;
      return c != null && _hasExactRow(e, c) ? 0 : 1;
    }

    List<int> key(String e) => [cylRank(e), fuelRank(e), exactRank(e)];

    int cmp(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        final c = a[i].compareTo(b[i]);
        if (c != 0) return c;
      }
      return 0;
    }

    final order = <String>[...candidates]..sort((a, b) {
        final c = cmp(key(a), key(b));
        if (c != 0) return c;
        return _engines.indexOf(a).compareTo(_engines.indexOf(b));
      });
    final first = order.first;
    final firstKey = key(first);
    final firstLit = OnlineSpecVariant.parseLeadingEngineLiters(first);
    final firstSfx = _suffixOf(first);
    for (final e in order.skip(1)) {
      final lit = OnlineSpecVariant.parseLeadingEngineLiters(e);
      if (lit == null || firstLit == null || (lit - firstLit).abs() >= _litreTol) {
        continue;
      }
      if (cmp(key(e), firstKey) != 0) continue;
      // Never trade a plain label for a diesel one (or vice versa) just
      // because no fuel preference was available to rank them.
      if (_labelIsDiesel(e) != _labelIsDiesel(first)) continue;
      final sfx = _suffixOf(e);
      if (sfx.length > firstSfx.length &&
          firstSfx.split('').every(sfx.contains)) {
        return e;
      }
    }
    return first;
  }

  /// One deterministic reconciliation pass after the user changed [changed].
  ///
  /// The changed field is preserved. Other fields keep their value while they
  /// stay compatible; only incompatible dependents move, and only to values
  /// the scoped CarNet rows establish.
  SellSpecSelection reconcile(SellSpecSelection cur, SellSpecField changed) {
    final engine = (cur.engine ?? '').trim();
    switch (changed) {
      case SellSpecField.engine:
        // The exact selected label is kept; only its trusted dependents follow.
        if (engine.isEmpty) return cur;
        return cur.copyWith(
          cylinders: cylindersFor(engine),
          fuel: fuelFor(engine),
        );
      case SellSpecField.cylinders:
        final c = cur.cylinders;
        if (c == null) return cur;
        if (engine.isNotEmpty) {
          final ec = cylindersFor(engine);
          // Compatible (or no evidence either way): never touch the engine.
          if (ec == null || ec == c) return cur;
        }
        final cands = _engines.where((e) => cylindersFor(e) == c).toList();
        if (cands.isEmpty) return cur;
        final pick = _pick(cands, preferFuel: cur.fuel, preferCylinders: c);
        return cur.copyWith(engine: pick, fuel: fuelFor(pick));
      case SellSpecField.fuel:
        final f = cur.fuel;
        if (f == null) return cur;
        if (engine.isNotEmpty && _fuelCompatible(engine, f)) {
          return cur.copyWith(cylinders: cylindersFor(engine));
        }
        final cands = _engines.where((e) => fuelsOf(e).contains(f)).toList();
        if (cands.isEmpty) return cur;
        final pick = _pick(
          cands,
          preferFuel: f,
          preferCylinders: cur.cylinders,
        );
        return cur.copyWith(engine: pick, cylinders: cylindersFor(pick));
    }
  }
}
