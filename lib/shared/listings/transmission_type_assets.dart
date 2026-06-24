/// Transmission-type artwork for filter tiles.
const Map<String, String> kTransmissionTypeImageAssets = {
  'automatic': 'assets/transmission_types/automatic.png',
  'manual': 'assets/transmission_types/manual.png',
};

String? transmissionTypeImageAsset(String? transmission) {
  if (transmission == null || transmission.isEmpty || transmission == 'Any') {
    return null;
  }
  return kTransmissionTypeImageAssets[transmission.trim().toLowerCase()];
}
