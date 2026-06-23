import 'dart:convert';
import 'dart:io';

/// Validates and pretty-prints [assets/car_catalog.json].
///
/// Run from repo root:
///   flutter pub run bin/export_car_catalog.dart
void main() {
  final out = File('assets/car_catalog.json');
  if (!out.existsSync()) {
    stderr.writeln('Missing assets/car_catalog.json');
    exit(1);
  }
  final data = json.decode(out.readAsStringSync());
  if (data is! Map<String, dynamic>) {
    stderr.writeln('car_catalog.json must be a JSON object');
    exit(1);
  }
  final brands = data['brands'];
  final models = data['models'];
  if (brands is! List || brands.isEmpty) {
    stderr.writeln('car_catalog.json must include non-empty brands');
    exit(1);
  }
  if (models is! Map || models.isEmpty) {
    stderr.writeln('car_catalog.json must include non-empty models');
    exit(1);
  }
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln(
    'Validated ${out.path} (${brands.length} brands, ${models.length} model groups)',
  );
}
