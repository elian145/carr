/// Canonical codes for listing / filter "region specs" (lowercase API / DB values).
const List<String> kCarRegionSpecCodes = [
  'us',
  'gcc',
  'iraq',
  'canada',
  'eu',
  'cn',
  'korea',
  'ru',
  'iran',
];

bool isValidCarRegionSpecCode(String? s) {
  if (s == null || s.isEmpty) return false;
  return kCarRegionSpecCodes.contains(s.trim().toLowerCase());
}
