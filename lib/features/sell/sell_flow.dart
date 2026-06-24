import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import '../../data/car_name_translations.dart';
import '../../features/listing/car_listing_specs_grid.dart' as car_listing_specs_grid;
import '../../shared/listings/listing_identity.dart' as listing_identity;
import '../../features/listing/listing_spec_item.dart';
import '../../globals.dart';
import '../../l10n/app_localizations.dart';
import '../../models/online_spec_variant.dart';
import '../../pages/listing_image_gallery_page.dart';
import '../../services/ai_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/car_service.dart';
import '../../services/car_spec_index.dart';
import '../../shared/auth/phone_verification_gate.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/errors/user_error_text.dart';
import '../../shared/i18n/digits.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/i18n/listing_field_labels.dart';
import '../../shared/i18n/listing_value_labels.dart';
import '../../shared/i18n/locale_formatting.dart';
import '../../shared/i18n/region_spec_labels.dart' as region_spec_labels;
import '../../shared/listings/body_type_assets.dart' as body_type_assets;
import '../../shared/listings/body_type_image_widget.dart' as body_type_image;
import '../../shared/listings/engine_size_filter_options.dart';
import '../../shared/listings/listing_uploaded_ago.dart';
import '../../shared/media/media_url.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
import '../../shared/prefs/sell_draft_media_persistence.dart';
import '../../shared/prefs/sell_draft_step.dart';
import '../../shared/text/pretty_title_case.dart';
import '../../shared/ui/keyboard.dart';
import '../../theme_provider.dart';
import 'sell_draft_helpers.dart' as sell_draft_helpers;
import 'sell_listing_payload.dart';
import 'sell_brand_slug.dart';
import 'sell_currency_convert.dart';
import 'sell_fancy_selector.dart' as sell_fancy_selector;
import 'sell_video_helpers.dart' as sell_video_helpers;

part 'sell_car_page_fields.dart';
part 'sell_car_page_draft_persist.dart';
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

int _maxSellDraftStep(int a, int b, [int c = 0]) =>
    maxSellDraftStep(a, b, c);

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

int _readSellDraftStepDynamic(dynamic raw, {int maxIdx = 4}) =>
    readSellDraftStepDynamic(raw, maxIdx: maxIdx);

int _mergeSellDraftStep({int? jsonStep, int? prefsStep}) =>
    mergeSellDraftStep(jsonStep: jsonStep, prefsStep: prefsStep);

void _dismissAnyKeyboard([BuildContext? context]) =>
    dismissAnyKeyboard(context);

void _debugLog(String message) => appLog(message);

String _trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) =>
    trLegacyText(context, en, ar: ar, ku: ku);

String _buildFullImageUrl(String rel) => buildLegacyFullImageUrl(rel);

Widget _listingNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) =>
    listingNetworkImage(url, fit: fit, width: width, height: height);

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
}) =>
    sell_fancy_selector.buildFancySelector(
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
) =>
    car_listing_specs_grid.buildCarListingSpecsGrid(context, car);

typedef _SpecItem = ListingSpecItem;

Future<http.MultipartFile> _buildVideoMultipartFile(XFile video) =>
    sell_video_helpers.buildVideoMultipartFile(video);

Future<String?> generateVideoThumbnail(String videoPath) =>
    sell_video_helpers.generateVideoThumbnail(videoPath);

String _pleaseFillRequiredGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.pleaseFillRequired;

Widget buildSellWizardNavRow(
  BuildContext context, {
  required VoidCallback onPrevious,
  required VoidCallback onNext,
}) {
  return Row(
    children: [
      Expanded(
        child: SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: onPrevious,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFF6B00)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)!.previousButton,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B00),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: SizedBox(
          height: 50,
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)!.nextStep,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Text(
                AppLocalizations.of(context)!.nextStep,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

String _photosRequiredTitleGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.photosRequired;

String _videosOptionalTitleGlobal(BuildContext context) =>
    AppLocalizations.of(context)!.videosOptional;

String _pleaseSelectPhotoTextGlobal(BuildContext context) =>
    pleaseSelectPhotoText(context);

String _listingSubmittedSuccessTextGlobal(BuildContext context) =>
    listingSubmittedSuccessText(context);
