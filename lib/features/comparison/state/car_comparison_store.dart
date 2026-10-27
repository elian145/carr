import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/auth/account_scope.dart';
import '../../../shared/debug/app_log.dart';
import '../../../shared/listings/listing_identity.dart';

class CarComparisonStore extends ChangeNotifier {
  final List<Map<String, dynamic>> _comparisonCars = [];

  CarComparisonStore() {
    _loadFromPrefs();
    AccountScope.addSessionChangedListener(_onSessionChanged);
    AccountScope.addActivatedListener(_onAccountActivated);
  }

  /// F-34: the list belongs to the signed-in account. On any authentication
  /// transition drop it from memory immediately (without saving -- the saved
  /// copy stays with its owner), then reload once the new owner's storage is
  /// active.
  void _onSessionChanged() {
    if (_comparisonCars.isEmpty) return;
    _comparisonCars.clear();
    notifyListeners();
  }

  void _onAccountActivated(String? owner) {
    _comparisonCars.clear();
    _loadFromPrefs();
  }

  @override
  void dispose() {
    AccountScope.removeSessionChangedListener(_onSessionChanged);
    AccountScope.removeActivatedListener(_onAccountActivated);
    super.dispose();
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
    final generation = AccountScope.generation;
    try {
      final sp = await SharedPreferences.getInstance();
      if (generation != AccountScope.generation) return;
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
    final generation = AccountScope.generation;
    try {
      final sp = await SharedPreferences.getInstance();
      if (generation != AccountScope.generation) return;
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
