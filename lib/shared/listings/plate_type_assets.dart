/// Kurdistan Region plate-type artwork for filter / picker tiles.
const Map<String, String> kPlateTypeImageAssets = {
  'private': 'assets/plate_types/private.png',
  'temporary': 'assets/plate_types/temporary.png',
  'commercial': 'assets/plate_types/commercial.png',
  'taxi': 'assets/plate_types/taxi.png',
};

String? plateTypeImageAsset(String? plateType) {
  if (plateType == null || plateType.isEmpty || plateType == 'Any') {
    return null;
  }
  return kPlateTypeImageAssets[plateType.trim().toLowerCase()];
}
