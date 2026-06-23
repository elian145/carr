import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/data/car_catalog.dart';

Future<void> _loadCatalogForTests() async {
  try {
    final raw = await rootBundle.loadString('assets/car_catalog.json');
    final data = json.decode(raw);
    if (data is Map<String, dynamic>) {
      CarCatalog.applyCatalogFromAsset(data);
    }
  } catch (_) {
    // Widget tests that need catalog should bundle the asset via pubspec.yaml.
  }
}

/// Runs before every test file so setUp/tearDown can use platform channels
/// (SharedPreferences, secure storage, etc.) without per-file boilerplate.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadCatalogForTests();
  await testMain();
}
