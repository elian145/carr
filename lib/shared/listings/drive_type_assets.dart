/// Drive-type artwork for filter tiles.
const Map<String, String> kDriveTypeImageAssets = {
  'fwd': 'assets/drive_types/fwd.png',
  'rwd': 'assets/drive_types/rwd.png',
  'awd': 'assets/drive_types/awd.png',
};

String? driveTypeImageAsset(String? driveType) {
  if (driveType == null || driveType.isEmpty || driveType == 'Any') {
    return null;
  }
  return kDriveTypeImageAssets[driveType.trim().toLowerCase()];
}
