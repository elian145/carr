/// Flag artwork for region-spec filter tiles.
const Map<String, String> kRegionSpecFlagAssets = {
  'us': 'assets/region_spec_flags/us.png',
  'gcc': 'assets/region_spec_flags/gcc.png',
  'iraq': 'assets/region_spec_flags/iraq.png',
  'canada': 'assets/region_spec_flags/canada.png',
  'eu': 'assets/region_spec_flags/eu.png',
  'cn': 'assets/region_spec_flags/cn.png',
  'korea': 'assets/region_spec_flags/korea.png',
  'ru': 'assets/region_spec_flags/ru.png',
  'iran': 'assets/region_spec_flags/iran.png',
};

String? regionSpecFlagAsset(String? code) {
  if (code == null || code.isEmpty || code == 'Any') {
    return null;
  }
  return kRegionSpecFlagAssets[code.trim().toLowerCase()];
}
