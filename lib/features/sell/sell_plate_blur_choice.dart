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
  final maxIdx = SellWizardSteps.lastIndex;
  if (carData['sell_wizard_v2'] == true) {
    return SellWizardSteps.clampIndex(step);
  }

  // Old: 0 Basic, 1 Details, 2 Pricing, 3 Photos, 4 Review
  // New: photos, basicInfo, carDetails, pricingContact, plateBlur, reviewSubmit
  const mapped = <int, int>{
    0: SellWizardSteps.basicInfo,
    1: SellWizardSteps.carDetails,
    2: SellWizardSteps.pricingContact,
    3: SellWizardSteps.photos,
    4: SellWizardSteps.reviewSubmit,
  };
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
