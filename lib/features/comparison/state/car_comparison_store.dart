import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/debug/app_log.dart';
import '../../../shared/listings/listing_identity.dart';

class CarComparisonStore extends ChangeNotifier {
  final List<Map<String, dynamic>> _comparisonCars = [];

  CarComparisonStore() {
    _loadFromPrefs();
  }

  List<Map<String, dynamic>> get comparisonCars =>
      List.unmodifiable(_comparisonCars);

  bool get canAddMore => _comparisonCars.length < 5;

  int get comparisonCount => _comparisonCars.length;

  String? _carKey(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool isCarInComparison(String carId) {
    final candidate = carId.trim();
    if (candidate.isEmpty) return false;
    return _comparisonCars.any((car) => listingMatchesId(car, candidate));
  }

  void addCarToComparison(Map<String, dynamic> car) {
    if (_comparisonCars.length >= 5) return;
    final id = listingPrimaryId(car);
    if (id.isEmpty) {
      final fallback = _carKey(
        car['id'] ?? car['public_id'] ?? car['car_id'] ?? car['carId'],
      );
      if (fallback == null) return;
      if (isCarInComparison(fallback)) return;
      final normalized = Map<String, dynamic>.from(car);
      normalized['id'] = fallback;
      _comparisonCars.add(normalized);
      _saveToPrefs();
      notifyListeners();
      return;
    }
    if (!isCarInComparison(id)) {
      final normalized = Map<String, dynamic>.from(car);
      normalized['id'] = id;
      final publicId = (car['public_id'] ?? '').toString().trim();
      if (publicId.isNotEmpty) {
        normalized['public_id'] = publicId;
      }
      _comparisonCars.add(normalized);
      _saveToPrefs();
      notifyListeners();
    }
  }

  void removeCarFromComparison(String carId) {
    final candidate = carId.trim();
    if (candidate.isEmpty) return;
    _comparisonCars.removeWhere((car) => listingMatchesId(car, candidate));
    _saveToPrefs();
    notifyListeners();
  }

  void clearComparison() {
    _comparisonCars.clear();
    _saveToPrefs();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final List<String> encoded = _comparisonCars
          .map((e) => json.encode(e))
          .toList();
      await sp.setStringList('comparison_cars', encoded);
    } catch (e) {
      if (kDebugMode) {
        appLog('CarComparisonStore: failed saving prefs: $e');
      }
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final encoded = sp.getStringList('comparison_cars') ?? [];
      final List<Map<String, dynamic>> loaded = encoded
          .map<Map<String, dynamic>>(
            (s) => Map<String, dynamic>.from(json.decode(s)),
          )
          .toList();

      bool changed = false;
      for (final Map<String, dynamic> car in loaded) {
        final loadedId = listingPrimaryId(car);
        final resolvedId = loadedId.isNotEmpty
            ? loadedId
            : _carKey(car['id'] ?? car['car_id'] ?? car['carId'] ?? car['uuid']);
        if (resolvedId == null) continue;

        if (!isCarInComparison(resolvedId)) {
          final normalized = Map<String, dynamic>.from(car);
          normalized['id'] = resolvedId;
          _comparisonCars.add(normalized);
          changed = true;
        }
      }

      if (changed) notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        appLog('CarComparisonStore: failed loading prefs: $e');
      }
    }
  }
}
