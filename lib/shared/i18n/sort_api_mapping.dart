import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

const _apiSortKeys = <String>{
  'newest',
  'price_asc',
  'price_desc',
  'year_desc',
  'year_asc',
  'mileage_asc',
  'mileage_desc',
};

/// Resolves a sort UI label or API key to an API parameter.
///
/// Returns `null` for empty/default. Returns the original [sortOption] when
/// unrecognized (legacy passthrough).
String? _resolveSortApiKey(String sortOption) {
  final trimmed = sortOption.trim();
  if (trimmed.isEmpty) return null;

  if (_apiSortKeys.contains(trimmed)) return trimmed;

  switch (trimmed) {
    // English
    case 'Default':
      return null;
    case 'Newest':
      return 'newest';
    case 'Price (Low to High)':
      return 'price_asc';
    case 'Price (High to Low)':
      return 'price_desc';
    case 'Year (Newest)':
      return 'year_desc';
    case 'Year (Oldest)':
      return 'year_asc';
    case 'Mileage (Low to High)':
      return 'mileage_asc';
    case 'Mileage (High to Low)':
      return 'mileage_desc';

    // Arabic
    case 'افتراضي':
      return null;
    case 'الأحدث':
      return 'newest';
    case 'السعر (تصاعدي)':
      return 'price_asc';
    case 'السعر (تنازلي)':
      return 'price_desc';
    case 'السنة (الأحدث)':
      return 'year_desc';
    case 'السنة (الأقدم)':
      return 'year_asc';
    case 'المسافة (تصاعدي)':
      return 'mileage_asc';
    case 'المسافة (تنازلي)':
      return 'mileage_desc';

    // Kurdish
    case 'بنەڕەتی':
      return null;
    case 'نوێترین':
      return 'newest';
    case 'نرخ (کەم بۆ زۆر)':
      return 'price_asc';
    case 'نرخ (زۆر بۆ کەم)':
      return 'price_desc';
    case 'ساڵ (نوێترین)':
      return 'year_desc';
    case 'ساڵ (کۆنترین)':
      return 'year_asc';
    case 'کێڵگە (کەم بۆ زۆر)':
      return 'mileage_asc';
    case 'کێڵگە (زۆر بۆ کەم)':
      return 'mileage_desc';

    case 'default':
      return null;

    default:
      // Sentinel: caller treats this as "unrecognized".
      return trimmed;
  }
}

bool _isResolvedKnownSort(String original, String? resolved) {
  if (resolved == null) {
    // null means default — only if original was a known default label/key
    switch (original.trim()) {
      case 'default':
      case 'Default':
      case 'افتراضي':
      case 'بنەڕەتی':
        return true;
      default:
        return false;
    }
  }
  if (_apiSortKeys.contains(resolved) && resolved != original.trim()) {
    return true; // mapped from a localized label
  }
  if (_apiSortKeys.contains(original.trim())) return true;
  return false;
}

String _apiKeyToLocalizedLabel(AppLocalizations loc, String apiKey) {
  switch (apiKey) {
    case 'newest':
      return loc.sort_newest;
    case 'price_asc':
      return loc.sort_price_low_high;
    case 'price_desc':
      return loc.sort_price_high_low;
    case 'year_desc':
      return loc.sort_year_newest;
    case 'year_asc':
      return loc.sort_year_oldest;
    case 'mileage_asc':
      return loc.sort_mileage_low_high;
    case 'mileage_desc':
      return loc.sort_mileage_high_low;
    default:
      return apiKey;
  }
}

/// Maps localized sort labels (any language) or API keys to backend sort parameters.
String? convertSortToApiValue(BuildContext context, String? sortOption) {
  if (sortOption == null || sortOption.isEmpty) return null;

  final loc = AppLocalizations.of(context)!;

  // Current-locale labels (covers future copy tweaks in arb files).
  if (sortOption == loc.defaultSort) return null;
  if (sortOption == loc.sort_newest) return 'newest';
  if (sortOption == loc.sort_price_low_high) return 'price_asc';
  if (sortOption == loc.sort_price_high_low) return 'price_desc';
  if (sortOption == loc.sort_year_newest) return 'year_desc';
  if (sortOption == loc.sort_year_oldest) return 'year_asc';
  if (sortOption == loc.sort_mileage_low_high) return 'mileage_asc';
  if (sortOption == loc.sort_mileage_high_low) return 'mileage_desc';

  final resolved = _resolveSortApiKey(sortOption);
  if (resolved == null) return null;
  if (_apiSortKeys.contains(resolved)) return resolved;
  // Unrecognized: preserve previous passthrough behavior.
  return sortOption;
}

/// Whether [sortOption] is a known sort label or API key.
bool isKnownSortOption(String? sortOption) {
  if (sortOption == null || sortOption.isEmpty) return false;
  final locResolved = _resolveSortApiKey(sortOption);
  return _isResolvedKnownSort(sortOption, locResolved);
}

/// Converts any known sort label/API key into the label for the current locale.
///
/// Unknown values are returned unchanged.
String localizeSortOption(BuildContext context, String? sortOption) {
  if (sortOption == null || sortOption.isEmpty) return sortOption ?? '';

  final loc = AppLocalizations.of(context)!;
  if (sortOption == loc.defaultSort) return loc.defaultSort;

  final api = convertSortToApiValue(context, sortOption);
  if (api == null) return loc.defaultSort;
  if (!_apiSortKeys.contains(api)) return sortOption;
  return _apiKeyToLocalizedLabel(loc, api);
}

/// Localized labels for the listing sort menu (Home and dealer inventory).
List<String> localizedListingSortOptions(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return [
    loc.defaultSort,
    loc.sort_newest,
    loc.sort_price_low_high,
    loc.sort_price_high_low,
    loc.sort_year_newest,
    loc.sort_year_oldest,
    loc.sort_mileage_low_high,
    loc.sort_mileage_high_low,
  ];
}
