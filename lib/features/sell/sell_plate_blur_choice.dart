part of 'sell_flow.dart';

/// Applies the user's plate-blur preference onto listing + damage images.
void applySellPlateBlurChoice(Map<String, dynamic> carData, bool useBlurred) {
  carData['use_blurred_plates'] = useBlurred;
  carData['sell_wizard_v2'] = true;

  List<dynamic> pickList({
    required String originalsKey,
    required String blurredKey,
    required String activeKey,
  }) {
    final originals = carData[originalsKey];
    final blurred = carData[blurredKey];
    final fallback = carData[activeKey];
    if (useBlurred && blurred is List && blurred.isNotEmpty) {
      return List<dynamic>.from(blurred);
    }
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    if (fallback is List) {
      return List<dynamic>.from(fallback);
    }
    return <dynamic>[];
  }

  carData['images'] = pickList(
    originalsKey: 'original_images',
    blurredKey: 'blurred_images',
    activeKey: 'images',
  );
  carData['damage_images'] = pickList(
    originalsKey: 'original_damage_images',
    blurredKey: 'blurred_damage_images',
    activeKey: 'damage_images',
  );
}

/// Migrates a persisted wizard step from the old 5-step order to the new 6-step order.
int migrateSellWizardStep(int step, Map<String, dynamic> carData) {
  final maxIdx = _SellCarPageFields._kSellStepCount - 1;
  if (carData['sell_wizard_v2'] == true) {
    return step.clamp(0, maxIdx);
  }

  // Old: 0 Basic, 1 Details, 2 Pricing, 3 Photos, 4 Review
  // New: 0 Photos, 1 Basic, 2 Details, 3 Pricing, 4 Blur choice, 5 Review
  const mapped = <int, int>{0: 1, 1: 2, 2: 3, 3: 0, 4: 5};
  final next = mapped[step] ?? step;

  // Best-effort dual media for older blurred drafts.
  final images = carData['images'];
  if (images is List && images.isNotEmpty) {
    carData.putIfAbsent('original_images', () => List<dynamic>.from(images));
    if (carData['images_processed'] == true) {
      carData.putIfAbsent('blurred_images', () => List<dynamic>.from(images));
    }
  }
  final damage = carData['damage_images'];
  if (damage is List && damage.isNotEmpty) {
    carData.putIfAbsent(
      'original_damage_images',
      () => List<dynamic>.from(damage),
    );
    if (carData['images_processed'] == true) {
      carData.putIfAbsent(
        'blurred_damage_images',
        () => List<dynamic>.from(damage),
      );
    }
  }

  carData['sell_wizard_v2'] = true;
  return next.clamp(0, maxIdx);
}
