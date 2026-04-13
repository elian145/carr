/// One coherent equipment set (engine size ↔ cylinders, etc.) from the bundled
/// catalog or legacy sell-flow storage — not tied to any external Car API.
class OnlineSpecVariant {
  const OnlineSpecVariant({
    this.engineSizeLiters,
    this.displacementSuffix = '',
    this.cylinderCount,
    this.seating,
    this.fuelEconomy,
    this.transmission,
    this.drivetrain,
    this.bodyType,
    this.engineType,
    this.fuelType,
  });

  final double? engineSizeLiters;
  /// Display only: `" D"`, `" T"`, `" TD"`, or `""` (leading space when non-empty).
  final String displacementSuffix;
  final int? cylinderCount;
  final int? seating;
  final String? fuelEconomy;
  final String? transmission;
  final String? drivetrain;
  final String? bodyType;
  final String? engineType;
  final String? fuelType;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'engine_l': engineSizeLiters,
        'eng_sfx': displacementSuffix,
        'cyl': cylinderCount,
        'seat': seating,
        'mpg': fuelEconomy,
        'tr': transmission,
        'drv': drivetrain,
        'body': bodyType,
        'engt': engineType,
        'fuel': fuelType,
      };

  factory OnlineSpecVariant.fromJson(Map<String, dynamic> m) {
    return OnlineSpecVariant(
      engineSizeLiters: (m['engine_l'] as num?)?.toDouble(),
      displacementSuffix: (m['eng_sfx'] ?? '').toString(),
      cylinderCount: (m['cyl'] as num?)?.toInt(),
      seating: (m['seat'] as num?)?.toInt(),
      fuelEconomy: m['mpg']?.toString(),
      transmission: m['tr']?.toString(),
      drivetrain: m['drv']?.toString(),
      bodyType: m['body']?.toString(),
      engineType: m['engt']?.toString(),
      fuelType: m['fuel']?.toString(),
    );
  }

  /// Leading litres token in UI/storage strings (`3.0`, `3.0 D`, `2.4 TD`, …).
  static double? parseLeadingEngineLiters(String? text) {
    if (text == null) return null;
    final m = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(text.trim());
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  /// [anchors] names which fields the user just changed (those gate the strict filter).
  /// Other parameters should reflect **current** form values: variants that disagree on those
  /// fields are dropped when possible so e.g. gasoline + AWD is not replaced by diesel + AWD.
  ///
  /// Keys: `e` engine L, `c` cylinders, `tr` transmission, `drv` drivetrain, `body`, `engt`,
  /// `fuel`, `mpg`, `seat`.
  static OnlineSpecVariant? matchBestAnchored(
    List<OnlineSpecVariant> variants,
    Set<String> anchors, {
    double? engineLiters,
    int? cylinders,
    String? transmission,
    String? drivetrain,
    String? bodyType,
    String? engineType,
    String? fuelType,
    String? fuelEconomy,
    int? seating,
    String? currentTransmission,
    String? currentDrivetrain,
    int? currentSeating,
  }) {
    bool anchoredOk(OnlineSpecVariant v) {
      if (anchors.contains('e') &&
          engineLiters != null &&
          v.engineSizeLiters != null) {
        if ((v.engineSizeLiters! - engineLiters).abs() > 0.06) return false;
      }
      if (anchors.contains('c') && cylinders != null && v.cylinderCount != null) {
        if (v.cylinderCount != cylinders) return false;
      }
      if (anchors.contains('tr') &&
          transmission != null &&
          v.transmission != null &&
          v.transmission != transmission) {
        return false;
      }
      if (anchors.contains('drv') &&
          drivetrain != null &&
          v.drivetrain != null &&
          v.drivetrain != drivetrain) {
        return false;
      }
      if (anchors.contains('body') &&
          bodyType != null &&
          v.bodyType != null &&
          v.bodyType != bodyType) {
        return false;
      }
      if (anchors.contains('engt') &&
          engineType != null &&
          v.engineType != null &&
          v.engineType != engineType) {
        return false;
      }
      if (anchors.contains('fuel') &&
          fuelType != null &&
          v.fuelType != null &&
          v.fuelType != fuelType) {
        return false;
      }
      if (anchors.contains('mpg') &&
          fuelEconomy != null &&
          v.fuelEconomy != null &&
          v.fuelEconomy != fuelEconomy) {
        return false;
      }
      if (anchors.contains('seat') && seating != null && v.seating != null) {
        if (v.seating != seating) return false;
      }
      return true;
    }

    var cands = variants.where(anchoredOk).toList();
    if (cands.isEmpty) return null;

    /// Keep variants consistent with selections the user did **not** change this gesture.
    bool locksOk(OnlineSpecVariant v) {
      if (!anchors.contains('engt') &&
          engineType != null &&
          v.engineType != null &&
          v.engineType != engineType) {
        return false;
      }
      if (!anchors.contains('fuel') &&
          fuelType != null &&
          v.fuelType != null &&
          v.fuelType != fuelType) {
        return false;
      }
      if (!anchors.contains('tr') &&
          transmission != null &&
          v.transmission != null &&
          v.transmission != transmission) {
        return false;
      }
      if (!anchors.contains('drv') &&
          drivetrain != null &&
          v.drivetrain != null &&
          v.drivetrain != drivetrain) {
        return false;
      }
      if (!anchors.contains('body') &&
          bodyType != null &&
          v.bodyType != null &&
          v.bodyType != bodyType) {
        return false;
      }
      if (!anchors.contains('e') &&
          engineLiters != null &&
          v.engineSizeLiters != null &&
          (v.engineSizeLiters! - engineLiters).abs() > 0.06) {
        return false;
      }
      if (!anchors.contains('c') &&
          cylinders != null &&
          v.cylinderCount != null &&
          v.cylinderCount != cylinders) {
        return false;
      }
      if (!anchors.contains('mpg') &&
          fuelEconomy != null &&
          v.fuelEconomy != null &&
          v.fuelEconomy != fuelEconomy) {
        return false;
      }
      if (!anchors.contains('seat') &&
          seating != null &&
          v.seating != null &&
          v.seating != seating) {
        return false;
      }
      return true;
    }

    final locked = cands.where(locksOk).toList();
    if (locked.isNotEmpty) {
      cands = locked;
    }

    if (cands.length == 1) return cands.first;

    OnlineSpecVariant? prefer(
      List<OnlineSpecVariant> list,
      bool Function(OnlineSpecVariant) p,
    ) {
      final x = list.where(p).toList();
      return x.length == 1 ? x.first : null;
    }

    if (!anchors.contains('tr') && currentTransmission != null) {
      final p = prefer(cands, (v) => v.transmission == currentTransmission);
      if (p != null) return p;
    }
    if (!anchors.contains('drv') && currentDrivetrain != null) {
      final p = prefer(cands, (v) => v.drivetrain == currentDrivetrain);
      if (p != null) return p;
    }
    if (!anchors.contains('seat') && currentSeating != null) {
      final p = prefer(cands, (v) => v.seating == currentSeating);
      if (p != null) return p;
    }

    int matchScore(OnlineSpecVariant v) {
      var s = 0;
      if (engineType != null && v.engineType == engineType) s += 8;
      if (fuelType != null && v.fuelType == fuelType) s += 8;
      if (transmission != null && v.transmission == transmission) s += 4;
      if (drivetrain != null && v.drivetrain == drivetrain) s += 4;
      if (bodyType != null && v.bodyType == bodyType) s += 2;
      if (engineLiters != null &&
          v.engineSizeLiters != null &&
          (v.engineSizeLiters! - engineLiters).abs() <= 0.06) {
        s += 4;
      }
      if (cylinders != null &&
          v.cylinderCount != null &&
          v.cylinderCount == cylinders) {
        s += 2;
      }
      if (seating != null && v.seating == seating) s += 1;
      if (fuelEconomy != null &&
          v.fuelEconomy != null &&
          v.fuelEconomy == fuelEconomy) {
        s += 1;
      }
      return s;
    }

    cands.sort((a, b) => matchScore(b).compareTo(matchScore(a)));
    return cands.first;
  }
}
