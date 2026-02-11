import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CarComparisonStore extends ChangeNotifier {
  final List<Map<String, dynamic>> _comparisonCars = [];

  CarComparisonStore() {
    _loadFromPrefs();
  }

  List<Map<String, dynamic>> get comparisonCars =>
      List.unmodifiable(_comparisonCars);

  bool get canAddMore => _comparisonCars.length < 5;

  int get comparisonCount => _comparisonCars.length;

  bool isCarInComparison(int carId) {
    return _comparisonCars.any((car) => car['id'] == carId);
  }

  void addCarToComparison(Map<String, dynamic> car) {
    if (_comparisonCars.length >= 5) return;
    if (!isCarInComparison(car['id'])) {
      _comparisonCars.add(car);
      _saveToPrefs();
      notifyListeners();
    }
  }

  void removeCarFromComparison(int carId) {
    _comparisonCars.removeWhere((car) => car['id'] == carId);
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
        debugPrint('CarComparisonStore: failed saving prefs: $e');
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
        final dynamic rawId =
            car['id'] ?? car['car_id'] ?? car['carId'] ?? car['uuid'];
        final int loadedId = rawId is int
            ? rawId
            : (rawId is String ? (int.tryParse(rawId) ?? rawId.hashCode) : -1);

        if (!_comparisonCars.any((c) => c['id'] == loadedId)) {
          final normalized = Map<String, dynamic>.from(car);
          normalized['id'] = loadedId;
          _comparisonCars.add(normalized);
          changed = true;
        }
      }

      if (changed) notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CarComparisonStore: failed loading prefs: $e');
      }
    }
  }
}
