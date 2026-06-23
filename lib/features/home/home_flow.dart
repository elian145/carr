import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' as services;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_api_base.dart' show getApiBase;
import '../../app/widgets/global_listing_card.dart';
import '../../app/widgets/main_shell_navigation.dart' as main_shell_navigation;
import '../../data/brand_logo_filenames.dart';
import '../../data/car_catalog.dart';
import '../../data/car_name_translations.dart';
import '../../features/home/home_feed_errors.dart';
import '../../features/home/home_brand_model_search.dart';
import '../../features/home/home_filter_chip_style.dart';
import '../../features/home/home_filter_chips.dart';
import '../../features/home/home_filter_persistence.dart';
import '../../features/home/home_filters_query.dart';
import '../../features/home/widgets/home_filter_chip.dart';
import '../../features/home/more_filters_dialog_style.dart';
import '../../features/home/widgets/home_feed_states.dart';
import '../../features/listing/listing_mappers.dart';
import '../../features/saved_searches/saved_search_home_bridge.dart';
import '../../l10n/app_localizations.dart';
import '../../models/online_spec_variant.dart';
import '../../pages/saved_searches_page.dart';
import '../../services/api_service.dart';
import '../../services/car_spec_index.dart';
import '../../services/saved_search_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart';
import '../../shared/i18n/sort_api_mapping.dart';
import '../../shared/listings/body_type_assets.dart' as body_type_assets;
import '../../shared/listings/body_type_image_widget.dart' as body_type_image;
import '../../shared/listings/listing_events.dart';
import '../../shared/listings/listing_identity.dart';
import '../../shared/listings/transmission_filter.dart';
import '../../shared/listings/engine_size_filter_options.dart';
import '../../shared/prefs/listing_layout_prefs.dart';
import '../../theme_provider.dart';

part 'home_page.dart';
part 'home_filter_catalog.dart';
part 'home_filter_persist.dart';
part 'home_filter_logic.dart';
part 'home_fetch.dart';
part 'home_filter_bar.dart';
part 'home_more_filters_price.dart';
part 'home_more_filters_year.dart';
part 'home_more_filters_mileage.dart';
part 'home_more_filters_body_color.dart';
part 'home_more_filters_mid.dart';
part 'home_more_filters_specs.dart';
part 'home_more_filters_dialog.dart';
part 'home_slivers.dart';
part 'home_build.dart';

const bool _kFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

List<String> get globalBodyTypes => body_type_assets.globalBodyTypes;
set globalBodyTypes(List<String> value) =>
    body_type_assets.globalBodyTypes = value;

Map<String, String> get globalBodyTypeAssetMap =>
    body_type_assets.globalBodyTypeAssetMap;
set globalBodyTypeAssetMap(Map<String, String> value) =>
    body_type_assets.globalBodyTypeAssetMap = value;

String _getBodyTypeAsset(String bodyType) =>
    body_type_assets.getBodyTypeAsset(bodyType);

Widget _buildBodyTypeImage(String assetPath) =>
    body_type_image.buildBodyTypeImage(assetPath);

String _trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) =>
    trLegacyText(context, en, ar: ar, ku: ku);

String _translatePlateTypeLegacy(BuildContext context, String raw) =>
    translatePlateTypeLabel(context, raw);

String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

String _localizeDigitsGlobal(BuildContext context, String input) =>
    localizeDigits(context, input);

String _engineSizeChipLabel(BuildContext context, String raw) =>
    engineSizeChipLabel(context, raw);

String _formatCurrencyGlobal(BuildContext context, dynamic raw) =>
    formatCurrency(context, raw);

String _cancelTextGlobal(BuildContext context) {
  return AppLocalizations.of(context)!.cancelAction;
}

String? _convertSortToApiValue(BuildContext context, String? sortOption) =>
    convertSortToApiValue(context, sortOption);

bool _isExcludedTransmissionFilter(String value) =>
    isExcludedTransmissionFilter(value);

void _debugLog(String message) => appLog(message);

/// Persists home feed scroll when main tabs use [Navigator.pushReplacement],
/// which disposes and rebuilds [HomePage].
class _HomeFeedScrollPersistence {
  _HomeFeedScrollPersistence._();

  static double? _pixels;

  static double get initialOffset => _pixels ?? 0;

  /// Home tab tapped while already on Home (scroll-to-top); keep bucket in sync.
  static void markTop() {
    _pixels = 0;
  }

  /// When the route is disposed before a deferred scroll restore runs, keep the target offset.
  static void savePixels(double pixels) {
    _pixels = pixels;
  }
}

void _switchMainTabNoAnimation(BuildContext context, String routeName) {
  main_shell_navigation.navigateMainShellTab(context, routeName);
}

Widget buildFloatingBottomNav(
  BuildContext context, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  bool solidBackground = false,
}) =>
    main_shell_navigation.buildFloatingBottomNav(
      context,
      currentIndex: currentIndex,
      onTap: onTap,
      solidBackground: solidBackground,
    );
