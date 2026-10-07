import 'sell_spec_reconcile.dart';

/// Search filter state for the three linked fields.
///
/// `null` engine / cylinders and an empty [fuels] list mean `Any`: an unselected
/// constraint that never constrains compatibility. [fuels] holds normalised
/// fuel keys (`diesel`, `gasoline`, ...); Search fuel is multi-select.
class SearchSpecState {
  const SearchSpecState({
    this.engine,
    this.cylinders,
    this.fuels = const [],
  });

  final String? engine;
  final int? cylinders;
  final List<String> fuels;

  @override
  bool operator ==(Object other) =>
      other is SearchSpecState &&
      other.engine == engine &&
      other.cylinders == cylinders &&
      other.fuels.length == fuels.length &&
      _sameOrder(other.fuels, fuels);

  static bool _sameOrder(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(engine, cylinders, Object.hashAll(fuels));

  @override
  String toString() => 'SearchSpecState($engine, $cylinders, $fuels)';
}

/// Search flavour of the shared trusted resolver ([SellSpecReconciler]): the
/// SAME relationship rules (exact CarNet rows; unanimous same-displacement
/// family for IQ-only labels; IQ model-level lists never fabricate a
/// combination), applied with Search's semantics:
///
///  * `Any` is an unselected constraint. Picking `Any` never reconciles, an
///    `Any` engine is never replaced by a chosen one (no fabricated constraint),
///    and an `Any` field never constrains compatibility.
///  * An engine pick keeps its exact label and fills the cylinders / fuel it
///    implies (engine -> cylinders / fuel is a functional dependency).
///  * Cylinder / fuel picks keep the current engine while it is compatible and
///    only otherwise move a CONCRETE engine to a deterministic trusted one.
///  * The field the user just changed is never altered; ambiguous or missing
///    evidence changes nothing.
///
/// Pure and cheap: it only reads the already scoped rows.
class SearchSpecReconciler {
  SearchSpecReconciler(this.core);

  final SellSpecReconciler core;

  SellSpecSelection _sel(String? engine, int? cylinders, String? fuel) =>
      SellSpecSelection(engine: engine, cylinders: cylinders, fuel: fuel);

  /// Fuels of [engine] when the current [fuels] contradict it.
  List<String> _fuelsForEngine(
    String engine,
    List<String> fuels, {
    required bool fillWhenAny,
  }) {
    final known = core.fuelsOf(engine);
    if (known.isEmpty) return fuels;
    if (fuels.isEmpty) {
      return fillWhenAny && known.length == 1 ? [known.first] : fuels;
    }
    if (fuels.any(known.contains)) return fuels;
    // A contradicting selection is replaced only by UNIQUE trusted evidence;
    // several possible fuels (or a plug-in hybrid) never rewrite the user's set.
    return known.length == 1 ? [known.first] : fuels;
  }

  /// The user picked a concrete engine.
  SearchSpecState afterEngine(SearchSpecState s) {
    final e = s.engine;
    if (e == null || e.isEmpty) return s;
    final r = core.reconcile(
      _sel(e, s.cylinders, s.fuels.isEmpty ? null : s.fuels.first),
      SellSpecField.engine,
    );
    return SearchSpecState(
      engine: e,
      cylinders: r.cylinders,
      fuels: _fuelsForEngine(e, s.fuels, fillWhenAny: true),
    );
  }

  /// The user picked a concrete cylinder count.
  SearchSpecState afterCylinders(SearchSpecState s) {
    final e = s.engine;
    final c = s.cylinders;
    if (e == null || e.isEmpty || c == null) return s;
    final r = core.reconcile(
      _sel(e, c, s.fuels.isEmpty ? null : s.fuels.first),
      SellSpecField.cylinders,
    );
    final next = r.engine;
    if (next == null || next == e) return s;
    return SearchSpecState(
      engine: next,
      cylinders: c,
      fuels: _fuelsForEngine(next, s.fuels, fillWhenAny: false),
    );
  }

  /// The user changed the fuel selection ([added] = the fuel just switched on).
  SearchSpecState afterFuel(SearchSpecState s, {String? added}) {
    final e = s.engine;
    if (e == null || e.isEmpty || s.fuels.isEmpty) return s;
    if (s.fuels.any((f) => core.fuelCompatible(e, f))) {
      final c = s.cylinders;
      if (c == null) return s;
      return SearchSpecState(
        engine: e,
        cylinders: core.cylindersFor(e) ?? c,
        fuels: s.fuels,
      );
    }
    final f = added != null && s.fuels.contains(added) ? added : s.fuels.first;
    final r = core.reconcile(_sel(e, s.cylinders, f), SellSpecField.fuel);
    final next = r.engine;
    if (next == null || next == e) return s;
    return SearchSpecState(
      engine: next,
      cylinders: r.cylinders ?? s.cylinders,
      fuels: s.fuels,
    );
  }

  /// Restored / re-validated filters: the stored engine (exact label) is
  /// authoritative; a conflicting CONCRETE cylinder / fuel follows it when the
  /// evidence is trusted. `Any` dependents stay `Any`.
  SearchSpecState afterRestore(SearchSpecState s) {
    final e = s.engine;
    if (e == null || e.isEmpty) return s;
    final c = s.cylinders;
    return SearchSpecState(
      engine: e,
      cylinders: c == null ? null : (core.cylindersFor(e) ?? c),
      fuels: _fuelsForEngine(e, s.fuels, fillWhenAny: false),
    );
  }
}
