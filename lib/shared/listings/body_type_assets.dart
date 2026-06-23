/// Dynamically discovered body types from assets (home filter / sell step 2).
List<String> globalBodyTypes = ['Any'];

/// Maps normalized body-type label → asset path under [assets/body_types_png/].
Map<String, String> globalBodyTypeAssetMap = {};

/// Resolves a body-type label to a bundled PNG asset path.
String getBodyTypeAsset(String bodyType) {
  if (bodyType.toLowerCase() == 'any') {
    return 'assets/body_types_png/sedan.png';
  }

  String normalizeTitle(String s) {
    final words = s
        .replaceAll(RegExp(r'[_\\-]+'), ' ')
        .trim()
        .split(RegExp(r'\\s+'));
    return words
        .map((w) {
          if (w.isEmpty) return w;
          final lettersOnly = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          if (lettersOnly.isNotEmpty && lettersOnly.length <= 3) {
            return w.toUpperCase();
          }
          return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
        })
        .join(' ');
  }

  final titleKey = normalizeTitle(bodyType);
  final mapped = globalBodyTypeAssetMap[titleKey];
  if (mapped != null && mapped.isNotEmpty) {
    return mapped;
  }

  final normalized = bodyType
      .toLowerCase()
      .replaceAll(RegExp(r'[_\\-]+'), ' ')
      .trim();

  switch (normalized) {
    case 'micro':
      return 'assets/body_types_png/micro.png';
    case 'cuv':
      return 'assets/body_types_png/cuv.png';
    case 'sedan':
      return 'assets/body_types_png/sedan.png';
    case 'suv':
      return 'assets/body_types_png/suv.png';
    case 'hatchback':
      return 'assets/body_types_png/hatchback.png';
    case 'coupe':
      return 'assets/body_types_png/coupe.png';
    case 'wagon':
    case 'station wagon':
    case 'estate':
      return 'assets/body_types_png/hatchback.png';
    case 'pickup':
      return 'assets/body_types_png/pickup.png';
    case 'roadster':
      return 'assets/body_types_png/roadster.png';
    case 'truck':
      return 'assets/body_types_png/truck.png';
    case 'minitruck':
    case 'mini truck':
      return 'assets/body_types_png/minitruck.png';
    case 'bigtruck':
    case 'big truck':
      return 'assets/body_types_png/bigtruck.png';
    case 'van':
      return 'assets/body_types_png/van.png';
    case 'minivan':
    case 'mini van':
    case 'mpv':
      return 'assets/body_types_png/van.png';
    case 'supercar':
      return 'assets/body_types_png/supercar.png';
    case 'cabriolet':
    case 'convertible':
    case 'cabrio':
      return 'assets/body_types_png/cabriolet.png';
    case 'motorcycle':
      return 'assets/body_types_png/motorcycle.png';
    case 'utv':
      return 'assets/body_types_png/UTV.png';
    case 'atv':
      return 'assets/body_types_png/ATV.png';
    default:
      return 'assets/body_types_png/sedan.png';
  }
}
