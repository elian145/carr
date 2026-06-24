part of 'car_spec_index.dart';

class CarSpecIndex extends CarSpecIndexBase
    with CarSpecIndexHelpers, CarSpecIndexCatalog, CarSpecIndexHomeFilter {
  static const String catalogAutofillModelOnly =
      CarSpecIndexBase.catalogAutofillModelOnly;
  static const String assetPath = CarSpecIndexBase.assetPath;

  static Future<CarSpecIndexLoadResult> loadWithResult() =>
      CarSpecIndexBase.loadWithResult();

  static Future<CarSpecIndex?> load() => CarSpecIndexBase.load();

  CarSpecIndex._({
    required Map<int, _Brand> brandsById,
    required Map<int, _Model> modelsById,
    required Map<int, List<_Model>> modelsByBrandId,
    required Map<int, List<_Trim>> trimsByModelId,
    required Map<int, _Spec> specByTrimId,
  }) : super._(
          brandsById: brandsById,
          modelsById: modelsById,
          modelsByBrandId: modelsByBrandId,
          trimsByModelId: trimsByModelId,
          specByTrimId: specByTrimId,
        );
}
