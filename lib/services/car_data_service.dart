import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/brand.dart';
import '../models/car_model.dart';
import '../models/trim.dart';

/// Loads and caches brand, model, and trim data from bundled JSON assets.
/// JSON is loaded once; subsequent calls use in-memory cache.
class CarDataService {
  CarDataService._();

  static final CarDataService instance = CarDataService._();

  static const String _brandsAsset = 'assets/data/brands.json';
  static const String _modelsAsset = 'assets/data/models.json';
  static const String _trimsAsset = 'assets/data/trims.json';

  List<Brand>? _brands;
  List<CarModel>? _models;
  List<Trim>? _trims;
  Future<void>? _loadFuture;

  static Brand? _tryParseBrand(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final id = e['id'];
    final name = e['name'];
    if (id == null || name == null) return null;
    return Brand(id: id.toString(), name: name.toString());
  }

  static CarModel? _tryParseModel(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final id = e['id'];
    final name = e['name'];
    final brandId = e['brandId'];
    if (id == null || name == null || brandId == null) return null;
    return CarModel(
      id: id.toString(),
      name: name.toString(),
      brandId: brandId.toString(),
    );
  }

  static Trim? _tryParseTrim(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final id = e['id'];
    final name = e['name'];
    final modelId = e['modelId'];
    if (id == null || name == null || modelId == null) return null;
    return Trim(
      id: id.toString(),
      name: name.toString(),
      modelId: modelId.toString(),
    );
  }

  /// Ensures all JSON assets are loaded. Safe to call repeatedly; loads only once.
  Future<void> _ensureLoaded() async {
    _loadFuture ??= _loadData();
    await _loadFuture;
  }

  Future<void> _loadData() async {
    try {
      final bundle = rootBundle;
      final results = await Future.wait(<Future<String>>[
        bundle.loadString(_brandsAsset),
        bundle.loadString(_modelsAsset),
        bundle.loadString(_trimsAsset),
      ]);
      final brandsRaw = json.decode(results[0]) as List<dynamic>;
      final modelsRaw = json.decode(results[1]) as List<dynamic>;
      final trimsRaw = json.decode(results[2]) as List<dynamic>;

      _brands = brandsRaw
          .map((e) => _tryParseBrand(e))
          .whereType<Brand>()
          .toList();
      _models = modelsRaw
          .map((e) => _tryParseModel(e))
          .whereType<CarModel>()
          .toList();
      _trims = trimsRaw
          .map((e) => _tryParseTrim(e))
          .whereType<Trim>()
          .toList();
    } catch (e, stackTrace) {
      _loadFuture = null;
      throw CarDataLoadException(
        'Failed to load car data from assets: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Returns all brands. Loads assets on first call; uses cache afterward.
  Future<List<Brand>> getBrands() async {
    await _ensureLoaded();
    return List.unmodifiable(_brands!);
  }

  /// Returns models for the given [brandId]. Loads assets on first call if needed.
  Future<List<CarModel>> getModelsByBrand(String brandId) async {
    await _ensureLoaded();
    return _models!.where((m) => m.brandId == brandId).toList();
  }

  /// Returns trims for the given [modelId]. Loads assets on first call if needed.
  Future<List<Trim>> getTrimsByModel(String modelId) async {
    await _ensureLoaded();
    return _trims!.where((t) => t.modelId == modelId).toList();
  }

  /// Returns a sorted list of brand display names.
  Future<List<String>> getBrandNames() async {
    await _ensureLoaded();
    return _brands!.map((b) => b.name).toList()..sort();
  }

  /// Returns a map of brand name → sorted list of model names.
  Future<Map<String, List<String>>> buildModelMap() async {
    await _ensureLoaded();
    final Map<String, List<String>> result = {};
    for (final brand in _brands!) {
      final brandModels = _models!.where((m) => m.brandId == brand.id).toList();
      if (brandModels.isNotEmpty) {
        result[brand.name] = brandModels.map((m) => m.name).toList()..sort();
      }
    }
    return result;
  }

  /// Returns a nested map of brand name → model name → list of trim names.
  Future<Map<String, Map<String, List<String>>>> buildTrimMap() async {
    await _ensureLoaded();
    final Map<String, Map<String, List<String>>> result = {};
    for (final brand in _brands!) {
      final brandModels = _models!.where((m) => m.brandId == brand.id).toList();
      for (final model in brandModels) {
        final modelTrims = _trims!.where((t) => t.modelId == model.id).toList();
        if (modelTrims.isNotEmpty) {
          result[brand.name] ??= {};
          result[brand.name]![model.name] =
              modelTrims.map((t) => t.name).toList()..sort();
        }
      }
    }
    return result;
  }
}

/// Thrown when car data JSON cannot be loaded or parsed.
class CarDataLoadException implements Exception {
  CarDataLoadException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'CarDataLoadException: $message${cause != null ? '\nCause: $cause' : ''}';
}
