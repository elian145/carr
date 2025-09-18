import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ku.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('ku'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CARZO'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get navAdd;

  /// No description provided for @navChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// No description provided for @navSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get navSaved;

  /// No description provided for @navLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get navLogin;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @addListingTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Listing'**
  String get addListingTitle;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginTitle;

  /// No description provided for @signupTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signupTitle;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @paymentHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get paymentHistoryTitle;

  /// No description provided for @paymentInitiateTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Initiate'**
  String get paymentInitiateTitle;

  /// No description provided for @chatConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Conversation'**
  String get chatConversationTitle;

  /// No description provided for @paymentStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Status'**
  String get paymentStatusTitle;

  /// No description provided for @editListingTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Listing'**
  String get editListingTitle;

  /// No description provided for @brandLabel.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get brandLabel;

  /// No description provided for @anyBrand.
  ///
  /// In en, this message translates to:
  /// **'Any Brand'**
  String get anyBrand;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @anyModel.
  ///
  /// In en, this message translates to:
  /// **'Any Model'**
  String get anyModel;

  /// No description provided for @yearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get yearLabel;

  /// No description provided for @anyYear.
  ///
  /// In en, this message translates to:
  /// **'Any Year'**
  String get anyYear;

  /// No description provided for @priceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceLabel;

  /// No description provided for @anyPrice.
  ///
  /// In en, this message translates to:
  /// **'Any Price'**
  String get anyPrice;

  /// No description provided for @mileageLabel.
  ///
  /// In en, this message translates to:
  /// **'Mileage'**
  String get mileageLabel;

  /// No description provided for @anyMileage.
  ///
  /// In en, this message translates to:
  /// **'Any Mileage'**
  String get anyMileage;

  /// No description provided for @conditionLabel.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get conditionLabel;

  /// No description provided for @anyCondition.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get anyCondition;

  /// No description provided for @transmissionLabel.
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get transmissionLabel;

  /// No description provided for @fuelTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Fuel Type'**
  String get fuelTypeLabel;

  /// No description provided for @bodyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Body Type'**
  String get bodyTypeLabel;

  /// No description provided for @cityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityLabel;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get applyFilters;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFilters;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @any.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get any;

  /// No description provided for @activeFilters.
  ///
  /// In en, this message translates to:
  /// **'Active Filters:'**
  String get activeFilters;

  /// No description provided for @moreFilters.
  ///
  /// In en, this message translates to:
  /// **'More Filters'**
  String get moreFilters;

  /// No description provided for @priceRange.
  ///
  /// In en, this message translates to:
  /// **'Price Range'**
  String get priceRange;

  /// No description provided for @minPrice.
  ///
  /// In en, this message translates to:
  /// **'Min Price'**
  String get minPrice;

  /// No description provided for @maxPrice.
  ///
  /// In en, this message translates to:
  /// **'Max Price'**
  String get maxPrice;

  /// No description provided for @anyMinPrice.
  ///
  /// In en, this message translates to:
  /// **'Any Min Price'**
  String get anyMinPrice;

  /// No description provided for @anyMaxPrice.
  ///
  /// In en, this message translates to:
  /// **'Any Max Price'**
  String get anyMaxPrice;

  /// No description provided for @yearRange.
  ///
  /// In en, this message translates to:
  /// **'Year Range'**
  String get yearRange;

  /// No description provided for @minYear.
  ///
  /// In en, this message translates to:
  /// **'Min Year'**
  String get minYear;

  /// No description provided for @maxYear.
  ///
  /// In en, this message translates to:
  /// **'Max Year'**
  String get maxYear;

  /// No description provided for @anyMinYear.
  ///
  /// In en, this message translates to:
  /// **'Any Min Year'**
  String get anyMinYear;

  /// No description provided for @anyMaxYear.
  ///
  /// In en, this message translates to:
  /// **'Any Max Year'**
  String get anyMaxYear;

  /// No description provided for @enterMinYear.
  ///
  /// In en, this message translates to:
  /// **'Enter min year'**
  String get enterMinYear;

  /// No description provided for @enterMaxYear.
  ///
  /// In en, this message translates to:
  /// **'Enter max year'**
  String get enterMaxYear;

  /// No description provided for @mileageRange.
  ///
  /// In en, this message translates to:
  /// **'Mileage Range'**
  String get mileageRange;

  /// No description provided for @minMileage.
  ///
  /// In en, this message translates to:
  /// **'Min Mileage'**
  String get minMileage;

  /// No description provided for @maxMileage.
  ///
  /// In en, this message translates to:
  /// **'Max Mileage'**
  String get maxMileage;

  /// No description provided for @enterMinMileage.
  ///
  /// In en, this message translates to:
  /// **'Enter min mileage'**
  String get enterMinMileage;

  /// No description provided for @enterMaxMileage.
  ///
  /// In en, this message translates to:
  /// **'Enter max mileage'**
  String get enterMaxMileage;

  /// No description provided for @titleStatus.
  ///
  /// In en, this message translates to:
  /// **'Title Status'**
  String get titleStatus;

  /// No description provided for @damagedParts.
  ///
  /// In en, this message translates to:
  /// **'Damaged Parts'**
  String get damagedParts;

  /// No description provided for @selectBodyType.
  ///
  /// In en, this message translates to:
  /// **'Select Body Type'**
  String get selectBodyType;

  /// No description provided for @colorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorLabel;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select Color'**
  String get selectColor;

  /// No description provided for @driveType.
  ///
  /// In en, this message translates to:
  /// **'Drive Type'**
  String get driveType;

  /// No description provided for @cylinderCount.
  ///
  /// In en, this message translates to:
  /// **'Cylinder Count'**
  String get cylinderCount;

  /// No description provided for @seating.
  ///
  /// In en, this message translates to:
  /// **'Seating'**
  String get seating;

  /// No description provided for @engineSizeL.
  ///
  /// In en, this message translates to:
  /// **'Engine Size (L)'**
  String get engineSizeL;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortBy;

  /// No description provided for @selectBrand.
  ///
  /// In en, this message translates to:
  /// **'Select Brand'**
  String get selectBrand;

  /// No description provided for @tapToSelectBrand.
  ///
  /// In en, this message translates to:
  /// **'Tap to select a brand'**
  String get tapToSelectBrand;

  /// No description provided for @trimLabel.
  ///
  /// In en, this message translates to:
  /// **'Trim'**
  String get trimLabel;

  /// No description provided for @loginRequired.
  ///
  /// In en, this message translates to:
  /// **'Login Required'**
  String get loginRequired;

  /// No description provided for @authenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'Authentication Required'**
  String get authenticationRequired;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @sendCodeFirst.
  ///
  /// In en, this message translates to:
  /// **'Send code first'**
  String get sendCodeFirst;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get typeMessage;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter phone number'**
  String get enterPhoneNumber;

  /// No description provided for @submitListing.
  ///
  /// In en, this message translates to:
  /// **'Submit Listing'**
  String get submitListing;

  /// No description provided for @specificationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get specificationsLabel;

  /// No description provided for @detail_condition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get detail_condition;

  /// No description provided for @detail_fuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get detail_fuel;

  /// No description provided for @detail_body.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get detail_body;

  /// No description provided for @detail_color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get detail_color;

  /// No description provided for @detail_drive.
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get detail_drive;

  /// No description provided for @detail_cylinders.
  ///
  /// In en, this message translates to:
  /// **'Cylinders'**
  String get detail_cylinders;

  /// No description provided for @detail_engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get detail_engine;

  /// No description provided for @detail_seating.
  ///
  /// In en, this message translates to:
  /// **'Seating'**
  String get detail_seating;

  /// No description provided for @value_condition_new.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get value_condition_new;

  /// No description provided for @value_condition_used.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get value_condition_used;

  /// No description provided for @value_transmission_automatic.
  ///
  /// In en, this message translates to:
  /// **'automatic'**
  String get value_transmission_automatic;

  /// No description provided for @value_transmission_manual.
  ///
  /// In en, this message translates to:
  /// **'manual'**
  String get value_transmission_manual;

  /// No description provided for @value_fuel_gasoline.
  ///
  /// In en, this message translates to:
  /// **'gasoline'**
  String get value_fuel_gasoline;

  /// No description provided for @value_fuel_diesel.
  ///
  /// In en, this message translates to:
  /// **'diesel'**
  String get value_fuel_diesel;

  /// No description provided for @value_fuel_electric.
  ///
  /// In en, this message translates to:
  /// **'electric'**
  String get value_fuel_electric;

  /// No description provided for @value_fuel_hybrid.
  ///
  /// In en, this message translates to:
  /// **'hybrid'**
  String get value_fuel_hybrid;

  /// No description provided for @value_fuel_lpg.
  ///
  /// In en, this message translates to:
  /// **'LPG'**
  String get value_fuel_lpg;

  /// No description provided for @value_fuel_plugin_hybrid.
  ///
  /// In en, this message translates to:
  /// **'plug-in hybrid'**
  String get value_fuel_plugin_hybrid;

  /// No description provided for @value_title_clean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get value_title_clean;

  /// No description provided for @value_title_damaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get value_title_damaged;

  /// No description provided for @value_drive_fwd.
  ///
  /// In en, this message translates to:
  /// **'fwd'**
  String get value_drive_fwd;

  /// No description provided for @value_drive_rwd.
  ///
  /// In en, this message translates to:
  /// **'rwd'**
  String get value_drive_rwd;

  /// No description provided for @value_drive_awd.
  ///
  /// In en, this message translates to:
  /// **'awd'**
  String get value_drive_awd;

  /// No description provided for @value_drive_4wd.
  ///
  /// In en, this message translates to:
  /// **'4wd'**
  String get value_drive_4wd;

  /// No description provided for @value_body_sedan.
  ///
  /// In en, this message translates to:
  /// **'sedan'**
  String get value_body_sedan;

  /// No description provided for @value_body_suv.
  ///
  /// In en, this message translates to:
  /// **'suv'**
  String get value_body_suv;

  /// No description provided for @value_body_hatchback.
  ///
  /// In en, this message translates to:
  /// **'hatchback'**
  String get value_body_hatchback;

  /// No description provided for @value_body_coupe.
  ///
  /// In en, this message translates to:
  /// **'coupe'**
  String get value_body_coupe;

  /// No description provided for @value_body_pickup.
  ///
  /// In en, this message translates to:
  /// **'pickup'**
  String get value_body_pickup;

  /// No description provided for @value_body_van.
  ///
  /// In en, this message translates to:
  /// **'van'**
  String get value_body_van;

  /// No description provided for @value_body_minivan.
  ///
  /// In en, this message translates to:
  /// **'minivan'**
  String get value_body_minivan;

  /// No description provided for @value_body_motorcycle.
  ///
  /// In en, this message translates to:
  /// **'motorcycle'**
  String get value_body_motorcycle;

  /// No description provided for @value_body_truck.
  ///
  /// In en, this message translates to:
  /// **'truck'**
  String get value_body_truck;

  /// No description provided for @value_body_cabriolet.
  ///
  /// In en, this message translates to:
  /// **'cabriolet'**
  String get value_body_cabriolet;

  /// No description provided for @value_body_roadster.
  ///
  /// In en, this message translates to:
  /// **'roadster'**
  String get value_body_roadster;

  /// No description provided for @value_body_micro.
  ///
  /// In en, this message translates to:
  /// **'micro'**
  String get value_body_micro;

  /// No description provided for @value_body_cuv.
  ///
  /// In en, this message translates to:
  /// **'cuv'**
  String get value_body_cuv;

  /// No description provided for @value_body_wagon.
  ///
  /// In en, this message translates to:
  /// **'wagon'**
  String get value_body_wagon;

  /// No description provided for @value_body_minitruck.
  ///
  /// In en, this message translates to:
  /// **'minitruck'**
  String get value_body_minitruck;

  /// No description provided for @value_body_bigtruck.
  ///
  /// In en, this message translates to:
  /// **'bigtruck'**
  String get value_body_bigtruck;

  /// No description provided for @value_body_supercar.
  ///
  /// In en, this message translates to:
  /// **'supercar'**
  String get value_body_supercar;

  /// No description provided for @value_body_utv.
  ///
  /// In en, this message translates to:
  /// **'utv'**
  String get value_body_utv;

  /// No description provided for @value_body_atv.
  ///
  /// In en, this message translates to:
  /// **'atv'**
  String get value_body_atv;

  /// No description provided for @value_body_scooter.
  ///
  /// In en, this message translates to:
  /// **'scooter'**
  String get value_body_scooter;

  /// No description provided for @value_body_super_bike.
  ///
  /// In en, this message translates to:
  /// **'super bike'**
  String get value_body_super_bike;

  /// No description provided for @unit_km.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get unit_km;

  /// No description provided for @unit_liter_suffix.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get unit_liter_suffix;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get min;

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get max;

  /// No description provided for @whatsappLabel.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Number (with country code)'**
  String get whatsappLabel;

  /// No description provided for @whatsappHint.
  ///
  /// In en, this message translates to:
  /// **'+9647XXXXXXXX'**
  String get whatsappHint;

  /// No description provided for @photosOptional.
  ///
  /// In en, this message translates to:
  /// **'Photos (optional)'**
  String get photosOptional;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add Photos'**
  String get addPhotos;

  /// No description provided for @addMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'Add More Photos'**
  String get addMorePhotos;

  /// No description provided for @defaultSort.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultSort;

  /// No description provided for @sort_price_low_high.
  ///
  /// In en, this message translates to:
  /// **'Price (Low to High)'**
  String get sort_price_low_high;

  /// No description provided for @sort_price_high_low.
  ///
  /// In en, this message translates to:
  /// **'Price (High to Low)'**
  String get sort_price_high_low;

  /// No description provided for @sort_year_newest.
  ///
  /// In en, this message translates to:
  /// **'Year (Newest)'**
  String get sort_year_newest;

  /// No description provided for @sort_year_oldest.
  ///
  /// In en, this message translates to:
  /// **'Year (Oldest)'**
  String get sort_year_oldest;

  /// No description provided for @sort_mileage_low_high.
  ///
  /// In en, this message translates to:
  /// **'Mileage (Low to High)'**
  String get sort_mileage_low_high;

  /// No description provided for @sort_mileage_high_low.
  ///
  /// In en, this message translates to:
  /// **'Mileage (High to Low)'**
  String get sort_mileage_high_low;

  /// No description provided for @sort_newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sort_newest;

  /// No description provided for @noCarsFound.
  ///
  /// In en, this message translates to:
  /// **'No cars found'**
  String get noCarsFound;

  /// No description provided for @carNotFound.
  ///
  /// In en, this message translates to:
  /// **'Car not found'**
  String get carNotFound;

  /// No description provided for @chatOnWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Chat on WhatsApp'**
  String get chatOnWhatsApp;

  /// No description provided for @unableToOpenWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Unable to open WhatsApp'**
  String get unableToOpenWhatsApp;

  /// No description provided for @backToList.
  ///
  /// In en, this message translates to:
  /// **'Back to list'**
  String get backToList;

  /// No description provided for @quickSell.
  ///
  /// In en, this message translates to:
  /// **'QUICK SELL'**
  String get quickSell;

  /// No description provided for @vehicleVideos.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Videos'**
  String get vehicleVideos;

  /// No description provided for @videoIndex.
  ///
  /// In en, this message translates to:
  /// **'Video {index}'**
  String videoIndex(Object index);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsEnablePush.
  ///
  /// In en, this message translates to:
  /// **'Enable Push Notifications'**
  String get settingsEnablePush;

  /// No description provided for @settingsClearCaches.
  ///
  /// In en, this message translates to:
  /// **'Clear Caches'**
  String get settingsClearCaches;

  /// No description provided for @settingsCachesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Home, Details, Favorites, Similar/Related'**
  String get settingsCachesSubtitle;

  /// No description provided for @settingsCleared.
  ///
  /// In en, this message translates to:
  /// **'Caches cleared'**
  String get settingsCleared;

  /// No description provided for @okAction.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okAction;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// No description provided for @passwordMin8.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMin8;

  /// No description provided for @otpSent.
  ///
  /// In en, this message translates to:
  /// **'OTP sent'**
  String get otpSent;

  /// No description provided for @otpFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send OTP'**
  String get otpFailed;

  /// No description provided for @otpFailedWithMsg.
  ///
  /// In en, this message translates to:
  /// **'Failed to send OTP: {msg}'**
  String otpFailedWithMsg(Object msg);

  /// No description provided for @devOtpCode.
  ///
  /// In en, this message translates to:
  /// **'Dev OTP: {code}'**
  String devOtpCode(Object code);

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @kurdish.
  ///
  /// In en, this message translates to:
  /// **'Kurdish'**
  String get kurdish;

  /// No description provided for @mileageRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mileage Range'**
  String get mileageRangeLabel;

  /// No description provided for @similarListings.
  ///
  /// In en, this message translates to:
  /// **'Similar Listings'**
  String get similarListings;

  /// No description provided for @relatedListings.
  ///
  /// In en, this message translates to:
  /// **'Related Listings'**
  String get relatedListings;

  /// No description provided for @listingUploadPartialFail.
  ///
  /// In en, this message translates to:
  /// **'Listing created, but photo upload failed ({code}).'**
  String listingUploadPartialFail(Object code);

  /// No description provided for @failedToSubmitListing.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit listing: {msg}'**
  String failedToSubmitListing(Object msg);

  /// No description provided for @couldNotSubmitListing.
  ///
  /// In en, this message translates to:
  /// **'Could not submit listing. Please try again.'**
  String get couldNotSubmitListing;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorTitle;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @haveAccountLogin.
  ///
  /// In en, this message translates to:
  /// **'Have an account? Login'**
  String get haveAccountLogin;

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'You are not logged in'**
  String get notLoggedIn;

  /// No description provided for @loginAction.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get loginAction;

  /// No description provided for @loggedIn.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loggedIn;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @devCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Dev code'**
  String get devCodeTitle;

  /// No description provided for @useCodeToVerify.
  ///
  /// In en, this message translates to:
  /// **'Use this code to verify: {code}'**
  String useCodeToVerify(Object code);

  /// No description provided for @verificationCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent'**
  String get verificationCodeSent;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'\$'**
  String get currencySymbol;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @selectDriveType.
  ///
  /// In en, this message translates to:
  /// **'Select drive type'**
  String get selectDriveType;

  /// No description provided for @selectCylinderCount.
  ///
  /// In en, this message translates to:
  /// **'Select cylinder count'**
  String get selectCylinderCount;

  /// No description provided for @selectSeating.
  ///
  /// In en, this message translates to:
  /// **'Select seating'**
  String get selectSeating;

  /// No description provided for @selectEngineSize.
  ///
  /// In en, this message translates to:
  /// **'Select engine size'**
  String get selectEngineSize;

  /// No description provided for @selectCity.
  ///
  /// In en, this message translates to:
  /// **'Select city'**
  String get selectCity;

  /// No description provided for @enterWhatsAppNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a WhatsApp number'**
  String get enterWhatsAppNumber;

  /// No description provided for @useInternationalFormat.
  ///
  /// In en, this message translates to:
  /// **'Use international format e.g. +9647XXXXXXX'**
  String get useInternationalFormat;

  /// No description provided for @anyOption.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get anyOption;

  /// No description provided for @city_baghdad.
  ///
  /// In en, this message translates to:
  /// **'Baghdad'**
  String get city_baghdad;

  /// No description provided for @city_basra.
  ///
  /// In en, this message translates to:
  /// **'Basra'**
  String get city_basra;

  /// No description provided for @city_erbil.
  ///
  /// In en, this message translates to:
  /// **'Erbil'**
  String get city_erbil;

  /// No description provided for @city_najaf.
  ///
  /// In en, this message translates to:
  /// **'Najaf'**
  String get city_najaf;

  /// No description provided for @city_karbala.
  ///
  /// In en, this message translates to:
  /// **'Karbala'**
  String get city_karbala;

  /// No description provided for @city_kirkuk.
  ///
  /// In en, this message translates to:
  /// **'Kirkuk'**
  String get city_kirkuk;

  /// No description provided for @city_mosul.
  ///
  /// In en, this message translates to:
  /// **'Mosul'**
  String get city_mosul;

  /// No description provided for @city_sulaymaniyah.
  ///
  /// In en, this message translates to:
  /// **'Sulaymaniyah'**
  String get city_sulaymaniyah;

  /// No description provided for @city_dohuk.
  ///
  /// In en, this message translates to:
  /// **'Dohuk'**
  String get city_dohuk;

  /// No description provided for @city_anbar.
  ///
  /// In en, this message translates to:
  /// **'Anbar'**
  String get city_anbar;

  /// No description provided for @city_halabja.
  ///
  /// In en, this message translates to:
  /// **'Halabja'**
  String get city_halabja;

  /// No description provided for @city_diyala.
  ///
  /// In en, this message translates to:
  /// **'Diyala'**
  String get city_diyala;

  /// No description provided for @city_diyarbakir.
  ///
  /// In en, this message translates to:
  /// **'Diyarbakir'**
  String get city_diyarbakir;

  /// No description provided for @city_maysan.
  ///
  /// In en, this message translates to:
  /// **'Maysan'**
  String get city_maysan;

  /// No description provided for @city_muthanna.
  ///
  /// In en, this message translates to:
  /// **'Muthanna'**
  String get city_muthanna;

  /// No description provided for @city_dhi_qar.
  ///
  /// In en, this message translates to:
  /// **'Dhi Qar'**
  String get city_dhi_qar;

  /// No description provided for @city_salaheldeen.
  ///
  /// In en, this message translates to:
  /// **'Salaheldeen'**
  String get city_salaheldeen;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'ku'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'ku':
      return AppLocalizationsKu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
