import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/brand_logo_filenames.dart';
import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../services/recently_viewed_service.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/listings/listing_card_data.dart' as listing_card_data;
import '../../shared/listings/listing_card_media.dart';
import '../../shared/listings/listing_status.dart';
import '../../shared/listings/listing_sold_badge.dart';
import '../../shared/media/media_url.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../theme_provider.dart';
import '../app_api_base.dart';
import 'listing_network_image.dart';

part 'global_listing_card_inner_text.dart';
part 'global_listing_card_carousel.dart';
part 'global_listing_card_build.dart';

/// Localized car title for cards: brand + model (translated), no trim, no year.
String localizedCarTitleForCard(BuildContext context, Map car) {
  final title = CarNameTranslations.getLocalizedCarTitleNoYear(
    context,
    Map<String, dynamic>.from(car),
  );
  final raw = title.isEmpty ? (car['title']?.toString() ?? '') : title;
  return prettyTitleCase(raw);
}

/// Trim line for listing cards (under brand+model, above price). Empty if none / base.
String localizedTrimForCard(BuildContext context, Map car) {
  final trim = car['trim']?.toString().trim();
  if (trim == null || trim.isEmpty) return '';
  if (trim.toLowerCase() == 'base') return '';
  return translateListingValue(context, trim) ?? trim;
}

/// Normalizes API listing / favorite payloads into the shape expected by [buildGlobalCarCard].
Map<String, dynamic> mapListingToGlobalCarCardData(
  BuildContext context,
  Map<String, dynamic> listing,
) =>
    listing_card_data.mapListingToGlobalCarCardData(context, listing);
