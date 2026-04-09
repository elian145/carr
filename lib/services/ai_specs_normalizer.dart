/// Coerce JSON from `/api/suggest-car-specs` into enums the sell flows already use.
class AiSpecsNormalizer {
  AiSpecsNormalizer._();

  static String transmissionApi(dynamic v) {
    final s = (v ?? 'automatic').toString().toLowerCase();
    return s.contains('manual') ? 'manual' : 'automatic';
  }

  static String drivetrainApi(dynamic v) {
    final s = (v ?? 'fwd').toString().toLowerCase();
    if (s.contains('4wd') || s == '4x4') return '4wd';
    switch (s) {
      case 'rwd':
        return 'rwd';
      case 'awd':
        return 'awd';
      case '4wd':
        return '4wd';
      case 'fwd':
      default:
        return 'fwd';
    }
  }

  static String bodyTypeApi(dynamic v) {
    final s = (v ?? 'sedan').toString().toLowerCase();
    const allowed = {'sedan', 'suv', 'hatchback', 'coupe', 'pickup', 'van'};
    if (allowed.contains(s)) return s;
    return 'sedan';
  }

  static String fuelApi(dynamic v) {
    var s = (v ?? 'gasoline').toString().toLowerCase();
    if (s == 'petrol' || s == 'gas') s = 'gasoline';
    if (s == 'phev') s = 'hybrid';
    const allowed = {'gasoline', 'diesel', 'electric', 'hybrid'};
    if (allowed.contains(s)) return s;
    return 'gasoline';
  }

  static double? engineLiters(dynamic v) {
    if (v == null) return null;
    final x = (v is num) ? v.toDouble() : double.tryParse(v.toString());
    if (x == null || x <= 0) return null;
    if (x < 0.3 || x > 20) return null;
    return double.parse(x.toStringAsFixed(1));
  }

  static int? cylinders(dynamic v) {
    if (v == null) return null;
    final x = (v is num) ? v.round() : int.tryParse(v.toString());
    if (x == null || x < 1 || x > 16) return null;
    return x;
  }

  static int? seating(dynamic v) {
    if (v == null) return null;
    final x = (v is num) ? v.round() : int.tryParse(v.toString());
    if (x == null || x < 1 || x > 15) return null;
    return x;
  }

  static String? fuelEconomy(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return s.length > 120 ? s.substring(0, 120) : s;
  }
}
