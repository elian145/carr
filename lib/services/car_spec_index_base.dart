part of 'car_spec_index.dart';

abstract class CarSpecIndexBase {
  /// Pass as [appTrim] on catalog autofill APIs to aggregate the **whole model line**
  /// in the spec file (ignore the user’s trim label).
  static const String catalogAutofillModelOnly = '';

  CarSpecIndexBase._({
    required Map<int, _Brand> brandsById,
    required Map<int, _Model> modelsById,
    required Map<int, List<_Model>> modelsByBrandId,
    required Map<int, List<_Trim>> trimsByModelId,
    required Map<int, _Spec> specByTrimId,
  })  : _brandsById = brandsById,
        _modelsById = modelsById,
        _modelsByBrandId = modelsByBrandId,
        _trimsByModelId = trimsByModelId,
        _specByTrimId = specByTrimId;

  final Map<int, _Brand> _brandsById;
  final Map<int, _Model> _modelsById;
  final Map<int, List<_Model>> _modelsByBrandId;
  final Map<int, List<_Trim>> _trimsByModelId;
  final Map<int, _Spec> _specByTrimId;

  static const assetPath = 'assets/car_spec_dataset.json';

  /// Loads the bundled JSON; surfaces failures instead of failing silently.
  ///
  /// Parsing runs in a background isolate ([compute]) so large datasets do not
  /// freeze the UI isolate. Asset IO still happens on the caller isolate.
  static Future<CarSpecIndexLoadResult> loadWithResult() async {
    try {
      final sw = Stopwatch()..start();
      final raw = await rootBundle.loadString(assetPath);
      appLog(
        'CarSpecIndex: read asset ${(raw.length / 1024 / 1024).toStringAsFixed(2)} MiB in ${sw.elapsedMilliseconds} ms',
      );
      final result = await compute(parseCarSpecDatasetJsonString, raw);
      appLog(
        'CarSpecIndex: parse + index build finished in ${sw.elapsedMilliseconds} ms (ok=${result.isOk})',
      );
      return result;
    } catch (e, st) {
      appLog('CarSpecIndex.loadWithResult failed: $e\n$st');
      return CarSpecIndexLoadResult._(
        errorMessage:
            'Could not load spec database ($e). Ensure assets/car_spec_dataset.json is listed under flutter: assets in pubspec.yaml, then stop the app and run again (full restart).',
      );
    }
  }

  /// Backward-compatible loader (null if anything goes wrong).
  static Future<CarSpecIndex?> load() async {
    final r = await loadWithResult();
    return r.index;
  }

  /// Dataset [Brand.id] for an app catalog brand name, or null if unknown.
}
