/// Fuel-type artwork for filter tiles.
const Map<String, String> kFuelTypeImageAssets = {
  'gasoline': 'assets/fuel_types/gasoline.png',
  'diesel': 'assets/fuel_types/diesel.png',
  'hybrid': 'assets/fuel_types/hybrid.png',
  'plug-in hybrid': 'assets/fuel_types/plug_in_hybrid.png',
  'plug_in_hybrid': 'assets/fuel_types/plug_in_hybrid.png',
  'plugin hybrid': 'assets/fuel_types/plug_in_hybrid.png',
  'electric': 'assets/fuel_types/electric.png',
};

String? fuelTypeImageAsset(String? fuelType) {
  if (fuelType == null || fuelType.isEmpty || fuelType == 'Any') {
    return null;
  }
  return kFuelTypeImageAssets[fuelType.trim().toLowerCase()];
}
