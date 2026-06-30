/// Iraqi unified plate system: governorate codes for plate-city filters.
///
/// Plate artwork comes from the official reference sheet (codes 11–29), used
/// as-is with no modifications.
const Set<String> kKrPlateCityCodes = {'21', '22', '23', '24'};

const Map<String, String> kPlateCityCodes = {
  'Baghdad': '11',
  'Basra': '14',
  'Erbil': '22',
  'Najaf': '28',
  'Karbala': '19',
  'Kirkuk': '25',
  'Mosul': '12',
  'Sulaymaniyah': '21',
  'Dohuk': '24',
  'Anbar': '15',
  'Halabja': '23',
  'Diyala': '20',
  'Diyarbakir': '21', // Turkish Diyarbakır province code
  'Maysan': '13',
  'Muthanna': '17',
  'Dhi Qar': '27',
  'Salaheldeen': '26',
};

/// Official reference sheet (source for plate-city PNGs).
const String kPlateCityReferenceSheetAsset =
    'assets/plate_types/plate_city_reference_sheet.png';

/// Governorate codes with official reference plate artwork (11–29).
const Set<String> kPlateCityReferenceCodes = {
  '11',
  '12',
  '13',
  '14',
  '15',
  '16',
  '17',
  '18',
  '19',
  '20',
  '21',
  '22',
  '23',
  '24',
  '25',
  '26',
  '27',
  '28',
  '29',
};

String _plateCityCodeImagePath(String code) =>
    'assets/plate_types/code_$code.png';

/// Cities offered in plate-city filters (excluding "Any").
const List<String> kPlateCityFilterOptions = [
  'Baghdad',
  'Basra',
  'Erbil',
  'Najaf',
  'Karbala',
  'Kirkuk',
  'Mosul',
  'Sulaymaniyah',
  'Dohuk',
  'Anbar',
  'Halabja',
  'Diyala',
  'Diyarbakir',
  'Maysan',
  'Muthanna',
  'Dhi Qar',
  'Salaheldeen',
];

String? plateCityImageAsset(String? city) {
  if (city == null || city.isEmpty || city == 'Any') {
    return null;
  }
  final code = kPlateCityCodes[city.trim()];
  if (code == null) {
    return null;
  }
  return _plateCityCodeImagePath(code);
}

String? plateCityCode(String? city) {
  if (city == null || city.isEmpty || city == 'Any') {
    return null;
  }
  return kPlateCityCodes[city.trim()];
}

String? plateCityCodeImageAsset(String? code) {
  if (code == null || code.isEmpty) {
    return null;
  }
  if (!kPlateCityReferenceCodes.contains(code)) {
    return null;
  }
  return _plateCityCodeImagePath(code);
}
