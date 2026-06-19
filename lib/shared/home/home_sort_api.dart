import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Maps localized home sort labels to backend `sort_by` query values.
String? homeSortToApiValue(BuildContext context, String? sortOption) {
  if (sortOption == null || sortOption.isEmpty) return null;

  final loc = AppLocalizations.of(context)!;

  if (sortOption == loc.defaultSort) return null;
  if (sortOption == loc.sort_newest) return 'newest';
  if (sortOption == loc.sort_price_low_high) return 'price_asc';
  if (sortOption == loc.sort_price_high_low) return 'price_desc';
  if (sortOption == loc.sort_year_newest) return 'year_desc';
  if (sortOption == loc.sort_year_oldest) return 'year_asc';
  if (sortOption == loc.sort_mileage_low_high) return 'mileage_asc';
  if (sortOption == loc.sort_mileage_high_low) return 'mileage_desc';

  return sortOption;
}
