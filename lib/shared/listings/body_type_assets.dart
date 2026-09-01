/// Body types for home filter / sell step 2 (populated from [ensureGlobalBodyTypesLoaded]).
List<String> globalBodyTypes = ['Any'];

/// Maps normalized body-type label → asset path under [assets/body_types_png/].
Map<String, String> globalBodyTypeAssetMap = {};

/// Light-mode body-type PNGs shipped in [pubspec.yaml] (no runtime manifest lookup).
const List<String> kBundledBodyTypeAssetPaths = [
  'assets/body_types_png/ATV.png',
  'assets/body_types_png/UTV.png',
  'assets/body_types_png/bigtruck.png',
  'assets/body_types_png/cabriolet.png',
  'assets/body_types_png/coupe.png',
  'assets/body_types_png/cuv.png',
  'assets/body_types_png/hatchback.png',
  'assets/body_types_png/micro.png',
  'assets/body_types_png/minitruck.png',
  'assets/body_types_png/minivan.png',
  'assets/body_types_png/motorcycle.png',
  'assets/body_types_png/pickup.png',
  'assets/body_types_png/roadster.png',
  'assets/body_types_png/scooter.png',
  'assets/body_types_png/sedan.png',
  'assets/body_types_png/super bike.png',
  'assets/body_types_png/supercar.png',
  'assets/body_types_png/suv.png',
  'assets/body_types_png/truck.png',
  'assets/body_types_png/van.png',
  'assets/body_types_png/wagon.png',
];

/// Populates [globalBodyTypes] and [globalBodyTypeAssetMap] from bundled assets.
void ensureGlobalBodyTypesLoaded() {
  if (globalBodyTypeAssetMap.isNotEmpty) return;
  final labelToAsset = discoverBodyTypeAssetMap(kBundledBodyTypeAssetPaths);
  if (labelToAsset.isEmpty) return;
  final labels = labelToAsset.keys.toList()..sort();
  globalBodyTypes = ['Any', ...labels];
  globalBodyTypeAssetMap = labelToAsset;
}

/// Builds the label → asset map from Flutter asset keys.
///
/// Skips `_dark` variants so they are not shown as separate body types.
Map<String, String> discoverBodyTypeAssetMap(Iterable<String> allAssets) {
  final btAssets = allAssets.where(_isDiscoverableBodyTypeAsset).toList();
  final labelToAsset = <String, String>{};
  for (final path in btAssets) {
    final fileName = path.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final base = dot <= 0 ? fileName : fileName.substring(0, dot);
    if (base.toLowerCase() == 'default') continue;

    final label = base
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : (w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '')),
        )
        .join(' ');

    if (!labelToAsset.containsKey(label)) {
      labelToAsset[label] = path;
      continue;
    }
    final existing = labelToAsset[label]!;
    final existingIsSvg = existing.toLowerCase().endsWith('.svg');
    final incomingIsSvg = path.toLowerCase().endsWith('.svg');
    if (!existingIsSvg && incomingIsSvg) {
      labelToAsset[label] = path;
    }
  }
  return labelToAsset;
}

bool _isDiscoverableBodyTypeAsset(String path) {
  if (path.contains('_dark')) return false;
  if (path.startsWith('assets/body_types_clean/') &&
      (path.endsWith('.svg') || path.endsWith('.png'))) {
    return true;
  }
  return path.startsWith('assets/body_types_png/') && path.endsWith('.png');
}

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
      return 'assets/body_types_png/wagon.png';
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
      return 'assets/body_types_png/minivan.png';
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

/// Body-type artwork for search filter tiles (null for [Any]).
String? bodyTypeImageAsset(String? bodyType) {
  if (bodyType == null || bodyType.isEmpty || bodyType == 'Any') {
    return null;
  }
  return getBodyTypeAsset(bodyType);
}
