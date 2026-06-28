import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:image_picker/image_picker.dart';

import '../../navigation/app_page_route.dart';
import '../../pages/listing_image_gallery_page.dart'
    show ListingPreviewMediaGridPage;
import '../../features/listing/listing_spec_item.dart';
import '../../l10n/app_localizations.dart';
import '../../models/online_spec_variant.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart';
import '../../shared/media/media_url.dart';
import '../../shared/vin/open_vin_search.dart';
/// Full URLs for listing images tagged `kind: damage` (shared by detail + specs grid).

part 'car_listing_specs_grid_damage.dart';
part 'car_listing_specs_grid_widgets.dart';
part 'car_listing_specs_grid_build.dart';
