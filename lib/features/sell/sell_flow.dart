/// Sell feature library (part / mixin map — M-15).
///
/// Entry: [SellCarPage] and step pages via this library (`sell_flow.dart`).
///
/// Shell: `_SellCarPageState` = Fields → DraftPersist → PlateBlur → DraftBanner.
/// Steps are separate State classes with their own mixin chains, e.g.:
/// - Step1: Fields → Catalog → PickersTrim → Pickers → Build
/// - Step2: Fields → CatalogOptions → CatalogHydrate → Pickers → Build*
/// - Step3–5 / blur: see `sell_stepN.dart` `with` clauses
///
/// Edit guide:
/// - draft save/restore → sell_car_page_draft_*.dart
/// - step N fields/UI → sell_stepN_*.dart
/// - listing payload → sell_listing_payload.dart (standalone helper)
///
/// State stays Provider-based; Riverpod migration is deferred.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../../theme/app_colors.dart';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_api_base.dart' show getApiBase;
import '../../app/widgets/listing_galleries.dart';
import '../../app/widgets/listing_network_image.dart';
import '../../data/car_catalog.dart';
import '../../data/car_catalog_loader.dart';
import '../../data/car_name_translations.dart';
import '../../features/listing/car_listing_specs_grid.dart'
    as car_listing_specs_grid;
import '../../shared/listings/listing_identity.dart' as listing_identity;
import '../../features/listing/listing_spec_icons.dart';
import '../../features/listing/listing_spec_item.dart';
import '../../globals.dart';
import '../../l10n/app_localizations.dart';
import '../../models/online_spec_variant.dart';
import '../../navigation/app_page_route.dart';
import '../../pages/listing_image_gallery_page.dart';
import '../../services/ai_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/car_service.dart';
import '../../services/car_spec_index.dart';
import '../../shared/auth/phone_verification_gate.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/debug/expected_client_noise.dart';
import '../../shared/errors/user_error_text.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart' as region_spec_labels;
import '../../shared/listings/body_type_assets.dart' as body_type_assets;
import '../../shared/listings/body_type_image_widget.dart' as body_type_image;
import '../../shared/listings/plate_city_assets.dart';
import '../../shared/listings/engine_size_filter_options.dart';
import '../../shared/listings/listing_uploaded_ago.dart';
import '../../shared/listings/listing_image_media.dart';
import '../../shared/media/media_url.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
import '../../shared/prefs/sell_draft_media_persistence.dart';
import '../../shared/prefs/sell_draft_step.dart';
import '../../shared/prefs/sell_pending_media_prefs.dart';
import 'sell_listing_media_upload.dart';
import 'sell_pending_media_resume.dart';
import 'sell_photo_prestage.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../shared/listings/drive_type_assets.dart';
import '../../shared/listings/fuel_type_assets.dart';
import '../../shared/listings/plate_type_assets.dart';
import '../../shared/listings/region_spec_assets.dart';
import '../../shared/listings/transmission_type_assets.dart';
import '../../shared/ui/filter_card_sections.dart';
import '../../shared/ui/filter_color_field.dart';
import '../../shared/ui/filter_make_section.dart';
import '../../shared/ui/make_model_keyword_search.dart';
import '../../shared/ui/filter_option_icons.dart';
import '../../shared/ui/keyboard.dart';
import '../../shared/ui/responsive.dart';
import '../../shared/ui/app_haptics.dart';
import '../../shared/ui/thousands_separator_input_formatter.dart';
import '../../theme_provider.dart';
import 'sell_draft_helpers.dart' as sell_draft_helpers;
import 'sell_wizard_steps.dart';
import 'sell_listing_payload.dart';
import 'sell_listing_submit_result.dart';
import 'sell_brand_slug.dart';
import '../../shared/listings/listing_status.dart';
import '../../shared/ui/brand_logo_image.dart';
import 'sell_currency_convert.dart';
import 'sell_fancy_selector.dart' as sell_fancy_selector;
import 'sell_video_helpers.dart' as sell_video_helpers;
import '../../shared/i18n/legacy_inline_text.dart';

part 'sell_car_page_fields.dart';
part 'sell_car_page_draft_persist.dart';
part 'sell_car_page_plate_blur.dart';
part 'sell_car_page_draft_banner.dart';
part 'sell_car_page.dart';
part 'sell_step1_fields.dart';
part 'sell_step1_catalog.dart';
part 'sell_step1_pickers_trim.dart';
part 'sell_step1_pickers.dart';
part 'sell_step1_build.dart';
part 'sell_step1.dart';
part 'sell_step2_fields.dart';
part 'sell_step2_catalog_options.dart';
part 'sell_step2_catalog_hydrate.dart';
part 'sell_step2_pickers.dart';
part 'sell_step2_build_core.dart';
part 'sell_step2_build_appearance.dart';
part 'sell_step2_build_mechanical.dart';
part 'sell_step2_build.dart';
part 'sell_step2.dart';
part 'sell_step3_build_price.dart';
part 'sell_step3_build_details.dart';
part 'sell_step3_build.dart';
part 'sell_step3_fields.dart';
part 'sell_step3_catalog.dart';
part 'sell_step3_pickers.dart';
part 'sell_step3.dart';
part 'sell_step4_build_intro.dart';
part 'sell_step4_build_photos.dart';
part 'sell_step4_build_damage.dart';
part 'sell_step4_build_videos.dart';
part 'sell_step4_build.dart';
part 'sell_step4_fields.dart';
part 'sell_step4_logic.dart';
part 'sell_step4.dart';
part 'sell_step4_preview_helpers.dart';
part 'sell_step4_preview_listing.dart';
part 'sell_step4_preview_review.dart';
part 'sell_plate_blur_choice.dart';
part 'sell_step_blur_choice.dart';
part 'sell_step_blur_choice_logic.dart';
part 'sell_step_blur_choice_build.dart';
part 'sell_step5_fields.dart';
part 'sell_step5_logic.dart';
part 'sell_step5_build.dart';
part 'sell_step5.dart';

const List<String> _kOnlineSpecOptionKeys = [
  '_online_opts_transmission',
  '_online_opts_drive',
  '_online_opts_body',
  '_online_opts_fuel',
  '_online_opts_engine_size',
  '_online_opts_cylinder',
  '_online_opts_seating',
];

const String _kOnlineSpecVariantsKey = '_online_spec_variants';

void _clearOnlineSpecOptionsInCarData(Map<String, dynamic> d) {
  for (final k in _kOnlineSpecOptionKeys) {
    d.remove(k);
  }
  d.remove(_kOnlineSpecVariantsKey);
}

void _applyCatalogSpecConstrainedOptionsToCarData(
  Map<String, dynamic> d,
  CatalogSpecFields f,
) {
  d['_online_opts_transmission'] = [sellFlowTransmissionLabel(f.transmission)];
  d['_online_opts_drive'] = [sellFlowDriveLabel(f.driveType)];
  d['_online_opts_body'] = [sellFlowBodyLabel(f.bodyType)];
  d['_online_opts_fuel'] = [sellFlowFuelLabel(f.fuelType)];
  if (f.engineSizeLiters != null && f.engineSizeLiters! > 0.001) {
    d['_online_opts_engine_size'] = [
      '${f.engineSizeLiters!.toStringAsFixed(1)}${f.displacementSuffix}',
    ];
  }
  if (f.cylinderCount != null && f.cylinderCount! > 0) {
    d['_online_opts_cylinder'] = ['${f.cylinderCount}'];
  }
  final seatLabel = sellFlowNearestSeatingLabel(f.seating);
  if (seatLabel != null) {
    d['_online_opts_seating'] = [seatLabel];
  }
}

void _applyCatalogSellFieldUnionToCarData(
  Map<String, dynamic> d,
  CatalogSellFieldOptions o,
) {
  d['_online_opts_transmission'] = o.transmissions.toList()..sort();
  d['_online_opts_drive'] = o.driveTypes.toList()..sort();
  d['_online_opts_body'] = o.bodyTypes.toList()..sort();
  d['_online_opts_fuel'] = o.fuelTypes.toList()..sort();
  if (o.engineSizes.isNotEmpty) {
    final eng = o.engineSizes.toList()
      ..sort((a, b) {
        final la = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final lb = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = la.compareTo(lb);
        if (c != 0) return c;
        return a.compareTo(b);
      });
    d['_online_opts_engine_size'] = eng;
  }
  if (o.cylinderCounts.isNotEmpty) {
    d['_online_opts_cylinder'] = o.cylinderCounts.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  }
  if (o.seatings.isNotEmpty) {
    d['_online_opts_seating'] = o.seatings.toList()..sort();
  }
}

OnlineSpecVariant _onlineSpecVariantFromCatalogFields(CatalogSpecFields f) {
  return OnlineSpecVariant(
    engineSizeLiters: f.engineSizeLiters,
    displacementSuffix: f.displacementSuffix,
    cylinderCount: f.cylinderCount,
    seating: f.seating,
    fuelEconomy: f.fuelEconomy,
    transmission: f.transmission,
    drivetrain: f.driveType,
    bodyType: f.bodyType,
    engineType: f.engineType,
    fuelType: f.fuelType,
  );
}

const List<String> kCarRegionSpecCodes = region_spec_labels.kCarRegionSpecCodes;

String _listingUploadedAgo(BuildContext context, Map car) =>
    listingUploadedAgo(context, car);

Map<String, dynamic> unwrapCarApiPayload(Map<String, dynamic> payload) =>
    listing_identity.unwrapCarApiPayload(payload);

String listingPrimaryId(Map<String, dynamic> listing) =>
    listing_identity.listingPrimaryId(listing);

int _maxSellDraftStep(int a, int b, [int c = 0]) => maxSellDraftStep(a, b, c);

bool isValidCarRegionSpecCode(String? s) =>
    region_spec_labels.isValidCarRegionSpecCode(s);

String _translatePlateTypeLegacy(BuildContext context, String raw) =>
    translatePlateTypeLabel(context, raw);

String _tapToSelectTextGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.tapToSelect;

String _quickSellTextGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.quickSell;

String carRegionSpecDisplayLabelLocalized(BuildContext context, String code) =>
    region_spec_labels.carRegionSpecDisplayLabelLocalized(context, code);

List<String> get globalBodyTypes => body_type_assets.globalBodyTypes;

Map<String, String> get globalBodyTypeAssetMap =>
    body_type_assets.globalBodyTypeAssetMap;

const String _sellDraftArchiveKey = sell_draft_helpers.kSellDraftArchiveKey;

String _newSellDraftId() => sell_draft_helpers.newSellDraftId();

List<Map<String, dynamic>> _decodeSellDraftArchive(String? raw) =>
    sell_draft_helpers.decodeSellDraftArchive(raw);

String _encodeSellDraftArchive(List<Map<String, dynamic>> drafts) =>
    sell_draft_helpers.encodeSellDraftArchive(drafts);

int _readSellDraftStepDynamic(
  dynamic raw, {
  int maxIdx = SellWizardSteps.lastIndex,
}) =>
    readSellDraftStepDynamic(raw, maxIdx: maxIdx);

int _mergeSellDraftStep({
  int? jsonStep,
  int? prefsStep,
  int maxIdx = SellWizardSteps.lastIndex,
}) =>
    mergeSellDraftStep(jsonStep: jsonStep, prefsStep: prefsStep, maxIdx: maxIdx);

void _dismissAnyKeyboard([BuildContext? context]) =>
    dismissAnyKeyboard(context);

void _debugLog(String message) => appLog(message);

String _buildFullImageUrl(String rel) => buildLegacyFullImageUrl(rel);

Widget _listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  double? width,
  double? height,
}) => listingNetworkImage(
  url,
  fit: fit,
  alignment: alignment,
  width: width,
  height: height,
);

String? _translateValueGlobal(BuildContext context, String? raw) =>
    translateListingValue(context, raw);

String _localizeDigitsGlobal(BuildContext context, String input) =>
    localizeDigits(context, input);

String _formatCurrencyGlobal(BuildContext context, dynamic raw) =>
    formatCurrency(context, raw);

NumberFormat _decimalFormatterGlobal(BuildContext context) =>
    decimalFormatterForLocale(context);

String _engineSizeSellRowLabel(BuildContext context, String raw) =>
    engineSizeSellRowLabel(context, raw);

String _getBodyTypeAsset(String bodyType) =>
    body_type_assets.getBodyTypeAsset(bodyType);

Widget _buildBodyTypeImage(String assetPath) =>
    body_type_image.buildBodyTypeImage(assetPath);

Widget buildFancySelector(
  BuildContext context, {
  IconData? icon,
  required String label,
  required String? value,
  Widget? leading,
  bool isError = false,
  String? currency,
}) => sell_fancy_selector.buildFancySelector(
  context,
  icon: icon,
  label: label,
  value: value,
  leading: leading,
  isError: isError,
  currency: currency,
);

Color _sellFlowManualFieldFill(BuildContext context) =>
    sell_fancy_selector.sellFlowManualFieldFill(context);

TextStyle _sellFlowManualFieldLabelStyle(BuildContext context) =>
    sell_fancy_selector.sellFlowManualFieldLabelStyle(context);

TextStyle _sellFlowManualFieldHintStyle(BuildContext context) =>
    sell_fancy_selector.sellFlowManualFieldHintStyle(context);

TextStyle _sellFlowManualFieldTextStyle(BuildContext context) =>
    sell_fancy_selector.sellFlowManualFieldTextStyle(context);

Widget buildCarListingSpecsGrid(
  BuildContext context,
  Map<String, dynamic> car,
) => car_listing_specs_grid.buildCarListingSpecsGrid(context, car);

typedef _SpecItem = ListingSpecItem;

Future<http.MultipartFile> _buildVideoMultipartFile(XFile video) =>
    sell_video_helpers.buildVideoMultipartFile(video);

Future<String?> generateVideoThumbnail(String videoPath) =>
    sell_video_helpers.generateVideoThumbnail(videoPath);

String _pleaseFillRequiredGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.pleaseFillRequired;

Widget buildSellWizardNavRow(
  BuildContext context, {
  required VoidCallback? onPrevious,
  required VoidCallback? onNext,
}) {
  final compact = AppResponsive.isCompactPhone(context);
  final previousButton = SizedBox(
    width: double.infinity,
    height: 50,
    child: OutlinedButton(
      onPressed: onPrevious,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.brandOrange),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          AppLocalizations.of(context)!.previousButton,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.brandOrange,
          ),
        ),
      ),
    ),
  );
  final nextButton = SizedBox(
    width: double.infinity,
    height: 50,
    child: Semantics(
      button: true,
      label: AppLocalizations.of(context)!.nextStep,
      child: ElevatedButton(
        onPressed: onNext,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppLocalizations.of(context)!.nextStep,
            maxLines: 1,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
  if (compact) {
    return Column(
      children: [previousButton, const SizedBox(height: 10), nextButton],
    );
  }
  return Row(
    children: [
      Expanded(child: previousButton),
      const SizedBox(width: 16),
      Expanded(child: nextButton),
    ],
  );
}

String _photosRequiredTitleGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.photosRequired;

String _videosOptionalTitleGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.videosOptional;

String _pleaseSelectPhotoTextGlobal(BuildContext context) =>
    pleaseSelectPhotoText(context);

String _listingSubmittedSuccessTextGlobal(
  BuildContext context, {
  required bool pendingReview,
}) =>
    pendingReview
        ? listingSubmittedPendingText(context)
        : listingSubmittedSuccessText(context);
