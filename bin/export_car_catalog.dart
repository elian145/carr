import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/data/car_catalog.dart';

/// Writes [assets/car_catalog.json] from embedded [CarCatalog] data.
///
/// Run from repo root:
///   flutter pub run bin/export_car_catalog.dart
void main() {
  final payload = CarCatalog.toAssetJson();
  final out = File('assets/car_catalog.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  final brands = (payload['brands'] as List).length;
  final models = (payload['models'] as Map).length;
  stdout.writeln(
    'Wrote ${out.path} ($brands brands, $models model groups)',
  );
}
