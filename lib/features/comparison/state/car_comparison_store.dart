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

  String? _carKey(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool isCarInComparison(String carId) {
    return _comparisonCars.any((car) => (car['id'] ?? car['public_id'] ?? '').toString() == carId);
  }

  void addCarToComparison(Map<String, dynamic> car) {
    if (_comparisonCars.length >= 5) return;
    final id = _carKey(car['id'] ?? car['public_id'] ?? car['car_id'] ?? car['carId']);
    if (id == null) return;
    if (!isCarInComparison(id)) {
      final normalized = Map<String, dynamic>.from(car);
      normalized['id'] = id;
      _comparisonCars.add(normalized);
      _saveToPrefs();
      notifyListeners();
    }
  }

  void removeCarFromComparison(String carId) {
    _comparisonCars.removeWhere((car) => (car['id'] ?? car['public_id'] ?? '').toString() == carId);
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
        final loadedId = _carKey(rawId);
        if (loadedId == null) continue;

        if (!_comparisonCars.any((c) => (c['id'] ?? '').toString() == loadedId)) {
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
