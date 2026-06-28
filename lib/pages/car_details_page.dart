import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/widgets/listing_network_image.dart';
import '../data/car_name_translations.dart';
import '../features/listing/car_details_listing_fields.dart';
import '../features/listing/car_details_recommendations.dart';
import '../features/listing/widgets/car_details_contact_bar.dart';
import '../features/listing/widgets/car_details_horizontal_list.dart';
import '../features/listing/widgets/car_details_seller_section.dart';
import '../features/chat/chat_pages.dart' as carzo_chat;
import '../features/comparison/widgets/comparison_button.dart';
import '../features/listing/car_listing_specs_grid.dart';
import '../l10n/app_localizations.dart';
import '../pages/listing_image_gallery_page.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/locale_formatting.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_management.dart'
    show
        confirmAndDeleteListing,
        confirmMarkListingSold,
        openEditListingPage,
        setListingSoldStatus;
import '../shared/listings/listing_owner.dart';
import '../shared/listings/listing_share.dart';
import '../shared/listings/listing_sold_badge.dart';
import '../shared/listings/listing_status.dart';
import '../shared/listings/listing_uploaded_ago.dart';
import '../shared/media/media_url.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/text/pretty_title_case.dart';
import '../shared/trust/report_dialog.dart';
import '../theme_provider.dart';
import '../widgets/network_video_thumbnail.dart';

// Placeholder classes for other pages

part 'car_details_page_fields.dart';
part 'car_details_page_titles.dart';
part 'car_details_page_owner.dart';
part 'car_details_page_media.dart';
part 'car_details_page_lifecycle.dart';
part 'car_details_page_load.dart';
part 'car_details_page_init.dart';
part 'car_details_page_contact.dart';
part 'car_details_page_build_hero.dart';
part 'car_details_page_build_body.dart';
part 'car_details_page_build.dart';

class CarDetailsPage extends StatefulWidget {
  final String carId;

  /// When false (default), owner edit/delete/sold controls are hidden — e.g. when
  /// opened from the home browse feed. Set true from My Listings.
  final bool allowOwnerManagement;

  const CarDetailsPage({
    super.key,
    required this.carId,
    this.allowOwnerManagement = false,
  });
  @override
  State<CarDetailsPage> createState() => _CarDetailsPageState();
}

class _CarDetailsPageState extends _CarDetailsPageFields
    with
        _CarDetailsPageTitles,
        _CarDetailsPageOwner,
        _CarDetailsPageMedia,
        _CarDetailsPageLifecycle,
        _CarDetailsPageLoad,
        _CarDetailsPageInit,
        _CarDetailsPageContact,
        _CarDetailsPageBuildHero,
        _CarDetailsPageBuildBody,
        _CarDetailsPageBuild {}
