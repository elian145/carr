part of 'sell_flow.dart';

/// Returns [images] with the cover photo first, without mutating the input.
/// Used for listing preview / submit while the sell grid keeps pick order.
List<dynamic> sellImagesWithPrimaryFirst(
  List<dynamic> images, {
  int primaryIndex = 0,
}) {
  if (images.isEmpty) return const <dynamic>[];
  final i = primaryIndex.clamp(0, images.length - 1);
  if (i == 0) return List<dynamic>.from(images);
  final copy = List<dynamic>.from(images);
  final item = copy.removeAt(i);
  copy.insert(0, item);
  return copy;
}

int sellPrimaryImageIndex(Map<String, dynamic> carData, {int length = 0}) {
  final raw = carData['primary_image_index'];
  final parsed = raw is int
      ? raw
      : int.tryParse(raw?.toString() ?? '') ?? 0;
  if (length <= 0) return parsed < 0 ? 0 : parsed;
  if (parsed < 0) return 0;
  if (parsed >= length) return 0;
  return parsed;
}

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
