part of 'car_spec_index.dart';

class _Brand {
  _Brand({required this.id, required this.name});
  final int id;
  final String name;

  static _Brand fromJson(Map<String, dynamic> j) => _Brand(
        id: _jsonInt(j['id']),
        name: (j['name'] ?? '').toString(),
      );
}

class _Model {
  _Model({required this.id, required this.brandId, required this.name});
  final int id;
  final int brandId;
  final String name;

  static _Model fromJson(Map<String, dynamic> j) => _Model(
        id: _jsonInt(j['id']),
        brandId: _jsonInt(j['brand_id']),
        name: (j['name'] ?? '').toString(),
      );
}

class _Trim {
  _Trim({
    required this.id,
    required this.modelId,
    required this.yearStart,
    required this.yearEnd,
    required this.name,
  });

  final int id;
  final int modelId;
  /// First model year (JSON `year`).
  final int yearStart;
  /// Last model year inclusive (`year_end` in JSON; if omitted, still in production → current year + 1).
  final int yearEnd;
  final String name;

  /// Representative year for sorting / legacy callers (same as [yearStart]).
  int get year => yearStart;

  bool coversYear(int y) => y >= yearStart && y <= yearEnd;

  static _Trim fromJson(Map<String, dynamic> j) {
    final ys = _jsonInt(j['year']);
    var ye = _jsonIntOpt(j['year_end']);
    if (ye != null && ye < ys) {
      ye = ys;
    }
    if (ye == null) {
      final cap = _openEndedModelYearCap();
      ye = ys > cap ? ys : cap;
    }
    return _Trim(
      id: _jsonInt(j['id']),
      modelId: _jsonInt(j['model_id']),
      yearStart: ys,
      yearEnd: ye,
      name: (j['name'] ?? '').toString(),
    );
  }
}

class _Spec {
  _Spec({
    required this.trimId,
    this.displacementCc,
    this.fuelType,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.seats,
    this.fuelConsumptionL100km,
    required this.rawPairs,
  });

  final int trimId;
  final int? displacementCc;
  final String? fuelType;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final int? seats;
  final double? fuelConsumptionL100km;
  final Map<String, String> rawPairs;

  static _Spec fromJson(Map<String, dynamic> j) {
    final raw = j['raw_spec_pairs'];
    final pairs = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        pairs['${k ?? ''}'] = '${v ?? ''}';
      });
    }
    return _Spec(
      trimId: _jsonInt(j['trim_id']),
      displacementCc: _jsonIntOpt(j['displacement_cc']),
      fuelType: j['fuel_type']?.toString(),
      transmission: j['transmission']?.toString(),
      drivetrain: j['drivetrain']?.toString(),
      bodyType: j['body_type']?.toString(),
      seats: _jsonIntOpt(j['seats']),
      fuelConsumptionL100km: (j['fuel_consumption_l_100km'] as num?)?.toDouble(),
      rawPairs: pairs,
    );
  }
}
