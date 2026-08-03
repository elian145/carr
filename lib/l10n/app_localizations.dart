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
  /// **'CarNet'**
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

  /// No description provided for @navDealers.
  ///
  /// In en, this message translates to:
  /// **'Dealerships'**
  String get navDealers;

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

  /// No description provided for @homeSearchHeading.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get homeSearchHeading;

  /// No description provided for @chatConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Conversation'**
  String get chatConversationTitle;

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

  /// No description provided for @allCities.
  ///
  /// In en, this message translates to:
  /// **'All cities'**
  String get allCities;

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

  /// No description provided for @regionSpecsLabel.
  ///
  /// In en, this message translates to:
  /// **'Region specs'**
  String get regionSpecsLabel;

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
  /// **'New'**
  String get value_condition_new;

  /// No description provided for @value_condition_used.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get value_condition_used;

  /// No description provided for @value_transmission_automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get value_transmission_automatic;

  /// No description provided for @value_transmission_manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get value_transmission_manual;

  /// No description provided for @value_fuel_gasoline.
  ///
  /// In en, this message translates to:
  /// **'Gasoline'**
  String get value_fuel_gasoline;

  /// No description provided for @value_fuel_diesel.
  ///
  /// In en, this message translates to:
  /// **'Diesel'**
  String get value_fuel_diesel;

  /// No description provided for @value_fuel_electric.
  ///
  /// In en, this message translates to:
  /// **'Electric'**
  String get value_fuel_electric;

  /// No description provided for @value_fuel_hybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get value_fuel_hybrid;

  /// No description provided for @value_fuel_lpg.
  ///
  /// In en, this message translates to:
  /// **'LPG'**
  String get value_fuel_lpg;

  /// No description provided for @value_fuel_plugin_hybrid.
  ///
  /// In en, this message translates to:
  /// **'Plug-in Hybrid'**
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

  /// No description provided for @titleStatusDamagedWithParts.
  ///
  /// In en, this message translates to:
  /// **'damaged ({count} parts)'**
  String titleStatusDamagedWithParts(String count);

  /// No description provided for @damageCrashPhotosSection.
  ///
  /// In en, this message translates to:
  /// **'Damage / crash photos (optional)'**
  String get damageCrashPhotosSection;

  /// No description provided for @addDamagePhotosCount.
  ///
  /// In en, this message translates to:
  /// **'Add damage photos ({count})'**
  String addDamagePhotosCount(Object count);

  /// No description provided for @damageImagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Damage images'**
  String get damageImagesTitle;

  /// No description provided for @viewDamagePhotosTooltip.
  ///
  /// In en, this message translates to:
  /// **'View damage or crash photos'**
  String get viewDamagePhotosTooltip;

  /// No description provided for @uploadingDamagePhotos.
  ///
  /// In en, this message translates to:
  /// **'Uploading damage photos...'**
  String get uploadingDamagePhotos;

  /// No description provided for @value_drive_fwd.
  ///
  /// In en, this message translates to:
  /// **'FWD'**
  String get value_drive_fwd;

  /// No description provided for @value_drive_rwd.
  ///
  /// In en, this message translates to:
  /// **'RWD'**
  String get value_drive_rwd;

  /// No description provided for @value_drive_awd.
  ///
  /// In en, this message translates to:
  /// **'AWD'**
  String get value_drive_awd;

  /// No description provided for @value_drive_4wd.
  ///
  /// In en, this message translates to:
  /// **'4WD'**
  String get value_drive_4wd;

  /// No description provided for @value_body_sedan.
  ///
  /// In en, this message translates to:
  /// **'Sedan'**
  String get value_body_sedan;

  /// No description provided for @value_body_suv.
  ///
  /// In en, this message translates to:
  /// **'SUV'**
  String get value_body_suv;

  /// No description provided for @value_body_hatchback.
  ///
  /// In en, this message translates to:
  /// **'Hatchback'**
  String get value_body_hatchback;

  /// No description provided for @value_body_coupe.
  ///
  /// In en, this message translates to:
  /// **'Coupe'**
  String get value_body_coupe;

  /// No description provided for @value_body_pickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get value_body_pickup;

  /// No description provided for @value_body_van.
  ///
  /// In en, this message translates to:
  /// **'Van'**
  String get value_body_van;

  /// No description provided for @value_body_minivan.
  ///
  /// In en, this message translates to:
  /// **'Minivan'**
  String get value_body_minivan;

  /// No description provided for @value_body_motorcycle.
  ///
  /// In en, this message translates to:
  /// **'Motorcycle'**
  String get value_body_motorcycle;

  /// No description provided for @value_body_truck.
  ///
  /// In en, this message translates to:
  /// **'Truck'**
  String get value_body_truck;

  /// No description provided for @value_body_cabriolet.
  ///
  /// In en, this message translates to:
  /// **'Cabriolet'**
  String get value_body_cabriolet;

  /// No description provided for @value_body_roadster.
  ///
  /// In en, this message translates to:
  /// **'Roadster'**
  String get value_body_roadster;

  /// No description provided for @value_body_micro.
  ///
  /// In en, this message translates to:
  /// **'Micro'**
  String get value_body_micro;

  /// No description provided for @value_body_cuv.
  ///
  /// In en, this message translates to:
  /// **'CUV'**
  String get value_body_cuv;

  /// No description provided for @value_body_wagon.
  ///
  /// In en, this message translates to:
  /// **'Wagon'**
  String get value_body_wagon;

  /// No description provided for @value_body_minitruck.
  ///
  /// In en, this message translates to:
  /// **'Minitruck'**
  String get value_body_minitruck;

  /// No description provided for @value_body_bigtruck.
  ///
  /// In en, this message translates to:
  /// **'Bigtruck'**
  String get value_body_bigtruck;

  /// No description provided for @value_body_supercar.
  ///
  /// In en, this message translates to:
  /// **'Supercar'**
  String get value_body_supercar;

  /// No description provided for @value_body_utv.
  ///
  /// In en, this message translates to:
  /// **'UTV'**
  String get value_body_utv;

  /// No description provided for @value_body_atv.
  ///
  /// In en, this message translates to:
  /// **'ATV'**
  String get value_body_atv;

  /// No description provided for @value_body_scooter.
  ///
  /// In en, this message translates to:
  /// **'Scooter'**
  String get value_body_scooter;

  /// No description provided for @value_body_super_bike.
  ///
  /// In en, this message translates to:
  /// **'Super Bike'**
  String get value_body_super_bike;

  /// No description provided for @unit_km.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get unit_km;

  /// No description provided for @unit_miles.
  ///
  /// In en, this message translates to:
  /// **'mi'**
  String get unit_miles;

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

  /// No description provided for @addMoreListings.
  ///
  /// In en, this message translates to:
  /// **'Add More Listings'**
  String get addMoreListings;

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

  /// No description provided for @chatOnCarzo.
  ///
  /// In en, this message translates to:
  /// **'Chat on CarNet'**
  String get chatOnCarzo;

  /// No description provided for @chatCarzoOwnListing.
  ///
  /// In en, this message translates to:
  /// **'You can\'t message yourself on your own listing.'**
  String get chatCarzoOwnListing;

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
  /// **'Home, Details, Favorites, Similar'**
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

  /// No description provided for @listingVinAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'This VIN is already used on another listing. Use a different VIN or edit your existing listing.'**
  String get listingVinAlreadyExists;

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

  /// No description provided for @sellTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sellTitle;

  /// No description provided for @sellRequiresAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sell'**
  String get sellRequiresAuthTitle;

  /// No description provided for @sellRequiresAuthBody.
  ///
  /// In en, this message translates to:
  /// **'Log in or create an account to list your car for sale.'**
  String get sellRequiresAuthBody;

  /// No description provided for @createListingButton.
  ///
  /// In en, this message translates to:
  /// **'Create listing'**
  String get createListingButton;

  /// No description provided for @creatingListing.
  ///
  /// In en, this message translates to:
  /// **'Creating listing...'**
  String get creatingListing;

  /// No description provided for @uploadingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Uploading photos...'**
  String get uploadingPhotos;

  /// No description provided for @uploadingVideos.
  ///
  /// In en, this message translates to:
  /// **'Uploading videos...'**
  String get uploadingVideos;

  /// No description provided for @addPhotosCount.
  ///
  /// In en, this message translates to:
  /// **'Add photos ({count})'**
  String addPhotosCount(Object count);

  /// No description provided for @addVideoCount.
  ///
  /// In en, this message translates to:
  /// **'Add video ({count})'**
  String addVideoCount(Object count);

  /// No description provided for @pleaseFixHighlightedFields.
  ///
  /// In en, this message translates to:
  /// **'Please fix the highlighted fields'**
  String get pleaseFixHighlightedFields;

  /// No description provided for @listingCreated.
  ///
  /// In en, this message translates to:
  /// **'Listing created'**
  String get listingCreated;

  /// No description provided for @listingTitle.
  ///
  /// In en, this message translates to:
  /// **'Listing'**
  String get listingTitle;

  /// No description provided for @shareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareAction;

  /// No description provided for @callAction.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callAction;

  /// No description provided for @chatAction.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatAction;

  /// No description provided for @favoriteAction.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteAction;

  /// No description provided for @favoritesAction.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesAction;

  /// No description provided for @editProfileAction.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileAction;

  /// No description provided for @descriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionTitle;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @sellerPhoneNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Seller phone not available'**
  String get sellerPhoneNotAvailable;

  /// No description provided for @couldNotStartCall.
  ///
  /// In en, this message translates to:
  /// **'Could not start a call'**
  String get couldNotStartCall;

  /// No description provided for @myListingsTitle.
  ///
  /// In en, this message translates to:
  /// **'My listings'**
  String get myListingsTitle;

  /// No description provided for @deleteListingTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete listing?'**
  String get deleteListingTitle;

  /// No description provided for @deleteListingBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove it from public listings.'**
  String get deleteListingBody;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @comparisonEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add cars to comparison from listings.'**
  String get comparisonEmptyHint;

  /// No description provided for @comparisonSpecLabel.
  ///
  /// In en, this message translates to:
  /// **'Spec'**
  String get comparisonSpecLabel;

  /// No description provided for @removeAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// No description provided for @settingsThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// No description provided for @settingsLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsLight;

  /// No description provided for @settingsDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsDark;

  /// No description provided for @enabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabledLabel;

  /// No description provided for @disabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabledLabel;

  /// No description provided for @accountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountLabel;

  /// No description provided for @apiLabel.
  ///
  /// In en, this message translates to:
  /// **'API'**
  String get apiLabel;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @favoritesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on a listing to save it here.'**
  String get favoritesEmptyHint;

  /// No description provided for @browseCarsAction.
  ///
  /// In en, this message translates to:
  /// **'Browse cars'**
  String get browseCarsAction;

  /// No description provided for @chatEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Message a seller from a listing to start a conversation.'**
  String get chatEmptyHint;

  /// No description provided for @recentlyViewedEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Open a car listing to add it here.'**
  String get recentlyViewedEmptyHint;

  /// No description provided for @noCarsFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting filters or browse all listings.'**
  String get noCarsFoundHint;

  /// No description provided for @descriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptionalLabel;

  /// No description provided for @plateBlurNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Plates are blurred only when you press Blur Plates.'**
  String get plateBlurNote;

  /// No description provided for @invalidField.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get invalidField;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @engineTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Engine type'**
  String get engineTypeLabel;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @chooseAuthMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose authentication method:'**
  String get chooseAuthMethodTitle;

  /// No description provided for @backAction.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backAction;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get verifyEmailTitle;

  /// No description provided for @accountCreatedAndEmailVerified.
  ///
  /// In en, this message translates to:
  /// **'Account created and email verified'**
  String get accountCreatedAndEmailVerified;

  /// No description provided for @emailVerifiedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Email verified successfully'**
  String get emailVerifiedSuccessfully;

  /// No description provided for @verificationFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Verification failed. Check the link or code and try again.'**
  String get verificationFailedMessage;

  /// No description provided for @verifyEmailInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code from the email we sent you, or open the verification link in this app.'**
  String get verifyEmailInstructions;

  /// No description provided for @verificationCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get verificationCodeLabel;

  /// No description provided for @verificationCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the code from the email or the link'**
  String get verificationCodeHint;

  /// No description provided for @pleaseEnterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter the verification code'**
  String get pleaseEnterVerificationCode;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully'**
  String get passwordResetSuccess;

  /// No description provided for @unableToResetPasswordCheckCode.
  ///
  /// In en, this message translates to:
  /// **'Unable to reset password. Please check the code and try again.'**
  String get unableToResetPasswordCheckCode;

  /// No description provided for @unableToResetPasswordTryLater.
  ///
  /// In en, this message translates to:
  /// **'Unable to reset password. Please try again later.'**
  String get unableToResetPasswordTryLater;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter the code you received and choose a new password.'**
  String get resetPasswordInstructions;

  /// No description provided for @resetCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Reset code'**
  String get resetCodeLabel;

  /// No description provided for @resetCodeHint.
  ///
  /// In en, this message translates to:
  /// **'6-digit or alphanumeric code'**
  String get resetCodeHint;

  /// No description provided for @pleaseEnterResetCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter the reset code'**
  String get pleaseEnterResetCode;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPasswordLabel;

  /// No description provided for @pleaseEnterNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new password'**
  String get pleaseEnterNewPassword;

  /// No description provided for @passwordUppercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one uppercase letter'**
  String get passwordUppercase;

  /// No description provided for @passwordLowercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one lowercase letter'**
  String get passwordLowercase;

  /// No description provided for @passwordNumber.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one number'**
  String get passwordNumber;

  /// No description provided for @passwordSpecialChar.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one special character'**
  String get passwordSpecialChar;

  /// No description provided for @confirmNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPasswordLabel;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @switchToLightMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to Light Mode'**
  String get switchToLightMode;

  /// No description provided for @switchToDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to Dark Mode'**
  String get switchToDarkMode;

  /// No description provided for @carIdChatRoom.
  ///
  /// In en, this message translates to:
  /// **'Car ID (chat room)'**
  String get carIdChatRoom;

  /// No description provided for @joinLabel.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinLabel;

  /// No description provided for @unknownSender.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownSender;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get noMessagesYet;

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String timeDaysAgo(Object count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String timeHoursAgo(Object count);

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String timeMinutesAgo(Object count);

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and all your data (listings, messages, favorites). If full deletion is blocked by system constraints, your account is deactivated and personal data and listing media are scrubbed. This cannot be undone.'**
  String get deleteAccountBody;

  /// No description provided for @passwordRequiredConfirm.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordRequiredConfirm;

  /// No description provided for @passwordOptionalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordOptionalConfirm;

  /// No description provided for @confirmWithPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your account password to confirm'**
  String get confirmWithPasswordHint;

  /// No description provided for @deleteMyAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteMyAccount;

  /// No description provided for @accountDeletedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted'**
  String get accountDeletedSnackbar;

  /// No description provided for @apiBaseTitle.
  ///
  /// In en, this message translates to:
  /// **'API base'**
  String get apiBaseTitle;

  /// No description provided for @apiBaseHint.
  ///
  /// In en, this message translates to:
  /// **'https://carr-5hrm.onrender.com'**
  String get apiBaseHint;

  /// No description provided for @resetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetButton;

  /// No description provided for @apiBaseUpdatedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'API base updated. Pull to refresh listings.'**
  String get apiBaseUpdatedSnackbar;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @analyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsTitle;

  /// No description provided for @failedToLoadListings.
  ///
  /// In en, this message translates to:
  /// **'Failed to load your listings'**
  String get failedToLoadListings;

  /// No description provided for @noListingsFound.
  ///
  /// In en, this message translates to:
  /// **'No Listings Found'**
  String get noListingsFound;

  /// No description provided for @createFirstListingForAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Create your first listing to see analytics'**
  String get createFirstListingForAnalytics;

  /// No description provided for @createListingButtonShort.
  ///
  /// In en, this message translates to:
  /// **'Create Listing'**
  String get createListingButtonShort;

  /// No description provided for @analyticsOverview.
  ///
  /// In en, this message translates to:
  /// **'Analytics Overview'**
  String get analyticsOverview;

  /// No description provided for @listingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get listingsLabel;

  /// No description provided for @viewsLabel.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get viewsLabel;

  /// No description provided for @messagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesLabel;

  /// No description provided for @callsLabel.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get callsLabel;

  /// No description provided for @sharesLabel.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get sharesLabel;

  /// No description provided for @favoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesLabel;

  /// No description provided for @analyticsDashboard.
  ///
  /// In en, this message translates to:
  /// **'Analytics Dashboard'**
  String get analyticsDashboard;

  /// No description provided for @performanceInsights.
  ///
  /// In en, this message translates to:
  /// **'Performance insights'**
  String get performanceInsights;

  /// No description provided for @performanceMetrics.
  ///
  /// In en, this message translates to:
  /// **'Performance Metrics'**
  String get performanceMetrics;

  /// No description provided for @engagementLabel.
  ///
  /// In en, this message translates to:
  /// **'Engagement'**
  String get engagementLabel;

  /// No description provided for @engagementRate.
  ///
  /// In en, this message translates to:
  /// **'Engagement Rate'**
  String get engagementRate;

  /// No description provided for @fuelEconomyLabel.
  ///
  /// In en, this message translates to:
  /// **'Fuel economy'**
  String get fuelEconomyLabel;

  /// No description provided for @comparisonTitle.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get comparisonTitle;

  /// No description provided for @noCarsSelected.
  ///
  /// In en, this message translates to:
  /// **'No cars selected'**
  String get noCarsSelected;

  /// No description provided for @carLabel.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get carLabel;

  /// No description provided for @personalInformationTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformationTitle;

  /// No description provided for @firstNameLabel.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstNameLabel;

  /// No description provided for @lastNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastNameLabel;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumberLabel;

  /// No description provided for @firstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get firstNameRequired;

  /// No description provided for @lastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get lastNameRequired;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get usernameRequired;

  /// No description provided for @usernameMin3.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get usernameMin3;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get emailInvalid;

  /// No description provided for @phoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phoneRequired;

  /// No description provided for @phoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number'**
  String get phoneInvalid;

  /// No description provided for @profilePictureTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Picture'**
  String get profilePictureTitle;

  /// No description provided for @tapCameraToChangeProfile.
  ///
  /// In en, this message translates to:
  /// **'Tap the camera icon to change your profile picture'**
  String get tapCameraToChangeProfile;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileTitle;

  /// No description provided for @saveChangesButton.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChangesButton;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get savingLabel;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully!'**
  String get profileUpdatedSuccess;

  /// No description provided for @failedToLoadUserData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load user data'**
  String get failedToLoadUserData;

  /// No description provided for @failedToUpdateProfile.
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile'**
  String get failedToUpdateProfile;

  /// No description provided for @failedToPickImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick image'**
  String get failedToPickImage;

  /// No description provided for @emailOrPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Email or Phone Number'**
  String get emailOrPhoneLabel;

  /// No description provided for @enterEmailOrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address or phone number'**
  String get enterEmailOrPhoneHint;

  /// No description provided for @forgotPasswordLink.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordLink;

  /// No description provided for @accountActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Actions'**
  String get accountActionsTitle;

  /// No description provided for @helpSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupportTitle;

  /// No description provided for @carComparisonCount.
  ///
  /// In en, this message translates to:
  /// **'Car Comparison'**
  String get carComparisonCount;

  /// No description provided for @addNewButton.
  ///
  /// In en, this message translates to:
  /// **'Add New +'**
  String get addNewButton;

  /// No description provided for @yourListingsCount.
  ///
  /// In en, this message translates to:
  /// **'Your Listings ({count})'**
  String yourListingsCount(Object count);

  /// No description provided for @verifyEmailAction.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get verifyEmailAction;

  /// No description provided for @sendVerificationLinkToEmail.
  ///
  /// In en, this message translates to:
  /// **'Send a verification link to your email'**
  String get sendVerificationLinkToEmail;

  /// No description provided for @verifyPhoneAction.
  ///
  /// In en, this message translates to:
  /// **'Verify phone'**
  String get verifyPhoneAction;

  /// No description provided for @phoneVerificationRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Verify your phone number in Profile before posting listings or sending messages.'**
  String get phoneVerificationRequiredMessage;

  /// No description provided for @receiveCodeBySms.
  ///
  /// In en, this message translates to:
  /// **'Receive a code by SMS'**
  String get receiveCodeBySms;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent. Check your inbox and spam.'**
  String get verificationEmailSent;

  /// No description provided for @codeSentEnterAbove.
  ///
  /// In en, this message translates to:
  /// **'Code sent. Enter it above and tap Verify.'**
  String get codeSentEnterAbove;

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyButton;

  /// No description provided for @pleaseEnter6DigitCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter the 6-digit code'**
  String get pleaseEnter6DigitCode;

  /// No description provided for @phoneVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Phone verified successfully'**
  String get phoneVerifiedSuccess;

  /// No description provided for @verifyPhoneDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify phone'**
  String get verifyPhoneDialogTitle;

  /// No description provided for @verifyPhoneDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'A 6-digit code will be sent to {phone}.'**
  String verifyPhoneDialogMessage(Object phone);

  /// No description provided for @sixDigitCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get sixDigitCodeLabel;

  /// No description provided for @sendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCodeButton;

  /// No description provided for @noListingsYet.
  ///
  /// In en, this message translates to:
  /// **'No Listings Yet'**
  String get noListingsYet;

  /// No description provided for @noListingsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t created any car listings yet.\nStart by adding your first car!'**
  String get noListingsEmptyHint;

  /// No description provided for @addYourFirstCar.
  ///
  /// In en, this message translates to:
  /// **'Add Your First Car'**
  String get addYourFirstCar;

  /// No description provided for @emailOrPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Email or phone number is required'**
  String get emailOrPhoneRequired;

  /// No description provided for @stepXOf5.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of 6'**
  String stepXOf5(Object step);

  /// No description provided for @basicInformationTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get basicInformationTitle;

  /// No description provided for @basicInformationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your car\'s basic details'**
  String get basicInformationSubtitle;

  /// No description provided for @carDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Car Details'**
  String get carDetailsTitle;

  /// No description provided for @carDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provide detailed information about your car'**
  String get carDetailsSubtitle;

  /// No description provided for @pricingContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Pricing & Contact'**
  String get pricingContactTitle;

  /// No description provided for @photosVideosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos & Videos'**
  String get photosVideosTitle;

  /// No description provided for @reviewSubmitTitle.
  ///
  /// In en, this message translates to:
  /// **'Review & Submit'**
  String get reviewSubmitTitle;

  /// No description provided for @selectBrandFirst.
  ///
  /// In en, this message translates to:
  /// **'Select brand first'**
  String get selectBrandFirst;

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'Next Step'**
  String get nextStep;

  /// No description provided for @previousButton.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previousButton;

  /// No description provided for @tapToSelect.
  ///
  /// In en, this message translates to:
  /// **'Tap to select'**
  String get tapToSelect;

  /// No description provided for @pleaseFillRequired.
  ///
  /// In en, this message translates to:
  /// **'Please complete'**
  String get pleaseFillRequired;

  /// No description provided for @pleaseSelectBrand.
  ///
  /// In en, this message translates to:
  /// **'Please select a brand'**
  String get pleaseSelectBrand;

  /// No description provided for @pleaseSelectModel.
  ///
  /// In en, this message translates to:
  /// **'Please select a model'**
  String get pleaseSelectModel;

  /// No description provided for @pleaseSelectTrim.
  ///
  /// In en, this message translates to:
  /// **'Please select a trim'**
  String get pleaseSelectTrim;

  /// No description provided for @pleaseSelectYear.
  ///
  /// In en, this message translates to:
  /// **'Please select a year'**
  String get pleaseSelectYear;

  /// No description provided for @pleaseEnterYear.
  ///
  /// In en, this message translates to:
  /// **'Please enter year'**
  String get pleaseEnterYear;

  /// No description provided for @enterYearHint.
  ///
  /// In en, this message translates to:
  /// **'Enter year (e.g. 2024)'**
  String get enterYearHint;

  /// No description provided for @yearInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid year'**
  String get yearInvalid;

  /// No description provided for @yearOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Year out of range'**
  String get yearOutOfRange;

  /// No description provided for @confirmYear.
  ///
  /// In en, this message translates to:
  /// **'Confirm year'**
  String get confirmYear;

  /// No description provided for @typeManually.
  ///
  /// In en, this message translates to:
  /// **'Type manually'**
  String get typeManually;

  /// No description provided for @mileageKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Mileage (km)'**
  String get mileageKmLabel;

  /// No description provided for @enterMileage.
  ///
  /// In en, this message translates to:
  /// **'Enter mileage'**
  String get enterMileage;

  /// No description provided for @pleaseEnterMileage.
  ///
  /// In en, this message translates to:
  /// **'Please enter mileage'**
  String get pleaseEnterMileage;

  /// No description provided for @invalidMileage.
  ///
  /// In en, this message translates to:
  /// **'Invalid mileage'**
  String get invalidMileage;

  /// No description provided for @mileageNegative.
  ///
  /// In en, this message translates to:
  /// **'Mileage cannot be negative'**
  String get mileageNegative;

  /// No description provided for @pleaseSelectMileage.
  ///
  /// In en, this message translates to:
  /// **'Please select mileage'**
  String get pleaseSelectMileage;

  /// No description provided for @confirmMileage.
  ///
  /// In en, this message translates to:
  /// **'Confirm mileage'**
  String get confirmMileage;

  /// No description provided for @pleaseSelectCondition.
  ///
  /// In en, this message translates to:
  /// **'Please select condition'**
  String get pleaseSelectCondition;

  /// No description provided for @pleaseSelectTransmission.
  ///
  /// In en, this message translates to:
  /// **'Please select transmission'**
  String get pleaseSelectTransmission;

  /// No description provided for @pleaseSelectFuelType.
  ///
  /// In en, this message translates to:
  /// **'Please select fuel type'**
  String get pleaseSelectFuelType;

  /// No description provided for @pleaseSelectBodyType.
  ///
  /// In en, this message translates to:
  /// **'Please select body type'**
  String get pleaseSelectBodyType;

  /// No description provided for @pleaseSelectColor.
  ///
  /// In en, this message translates to:
  /// **'Please select color'**
  String get pleaseSelectColor;

  /// No description provided for @pleaseSelectDriveType.
  ///
  /// In en, this message translates to:
  /// **'Please select drive type'**
  String get pleaseSelectDriveType;

  /// No description provided for @pleaseSelectRegionSpecs.
  ///
  /// In en, this message translates to:
  /// **'Please select region specs'**
  String get pleaseSelectRegionSpecs;

  /// No description provided for @pleaseSelectSeating.
  ///
  /// In en, this message translates to:
  /// **'Please select seating'**
  String get pleaseSelectSeating;

  /// No description provided for @pleaseSelectEngineSize.
  ///
  /// In en, this message translates to:
  /// **'Please select engine size'**
  String get pleaseSelectEngineSize;

  /// No description provided for @pleaseSelectCylinderCount.
  ///
  /// In en, this message translates to:
  /// **'Please select cylinder count'**
  String get pleaseSelectCylinderCount;

  /// No description provided for @contactForPrice.
  ///
  /// In en, this message translates to:
  /// **'Contact for price'**
  String get contactForPrice;

  /// No description provided for @comparisonCleared.
  ///
  /// In en, this message translates to:
  /// **'Comparison cleared'**
  String get comparisonCleared;

  /// No description provided for @clearComparisonTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear comparison?'**
  String get clearComparisonTitle;

  /// No description provided for @clearComparisonBody.
  ///
  /// In en, this message translates to:
  /// **'This removes all cars from your comparison list.'**
  String get clearComparisonBody;

  /// No description provided for @photosRequired.
  ///
  /// In en, this message translates to:
  /// **'Photos (Required)'**
  String get photosRequired;

  /// No description provided for @videosOptional.
  ///
  /// In en, this message translates to:
  /// **'Videos (Optional)'**
  String get videosOptional;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @sellButton.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sellButton;

  /// No description provided for @value_transmission_semi_automatic.
  ///
  /// In en, this message translates to:
  /// **'Semi-automatic'**
  String get value_transmission_semi_automatic;

  /// No description provided for @value_transmission_cvt.
  ///
  /// In en, this message translates to:
  /// **'CVT'**
  String get value_transmission_cvt;

  /// No description provided for @value_condition_certified.
  ///
  /// In en, this message translates to:
  /// **'Certified'**
  String get value_condition_certified;

  /// No description provided for @value_trim_base.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get value_trim_base;

  /// No description provided for @value_trim_sport.
  ///
  /// In en, this message translates to:
  /// **'Sport'**
  String get value_trim_sport;

  /// No description provided for @value_trim_luxury.
  ///
  /// In en, this message translates to:
  /// **'Luxury'**
  String get value_trim_luxury;

  /// No description provided for @value_color_black.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get value_color_black;

  /// No description provided for @value_color_white.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get value_color_white;

  /// No description provided for @value_color_silver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get value_color_silver;

  /// No description provided for @value_color_gray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get value_color_gray;

  /// No description provided for @value_color_red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get value_color_red;

  /// No description provided for @value_color_blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get value_color_blue;

  /// No description provided for @value_color_green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get value_color_green;

  /// No description provided for @value_color_yellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get value_color_yellow;

  /// No description provided for @value_color_orange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get value_color_orange;

  /// No description provided for @value_color_purple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get value_color_purple;

  /// No description provided for @value_color_brown.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get value_color_brown;

  /// No description provided for @value_color_beige.
  ///
  /// In en, this message translates to:
  /// **'Beige'**
  String get value_color_beige;

  /// No description provided for @value_color_gold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get value_color_gold;

  /// No description provided for @savedSearchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Searches'**
  String get savedSearchesTitle;

  /// No description provided for @noSavedSearchesYet.
  ///
  /// In en, this message translates to:
  /// **'No saved searches yet'**
  String get noSavedSearchesYet;

  /// No description provided for @savedSearchesHint.
  ///
  /// In en, this message translates to:
  /// **'Save a search from the Search page to get alerts for new matches'**
  String get savedSearchesHint;

  /// No description provided for @compareLabel.
  ///
  /// In en, this message translates to:
  /// **'compare +'**
  String get compareLabel;

  /// No description provided for @addedLabel.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get addedLabel;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @comparisonMaxLimit.
  ///
  /// In en, this message translates to:
  /// **'Maximum {max} cars can be compared'**
  String comparisonMaxLimit(Object max);

  /// No description provided for @removedFromComparison.
  ///
  /// In en, this message translates to:
  /// **'Removed from comparison'**
  String get removedFromComparison;

  /// No description provided for @addedToComparison.
  ///
  /// In en, this message translates to:
  /// **'Added to comparison ({count}/{max})'**
  String addedToComparison(Object count, Object max);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(Object count);

  /// No description provided for @noFiltersApplied.
  ///
  /// In en, this message translates to:
  /// **'No filters applied'**
  String get noFiltersApplied;

  /// No description provided for @unnamedSearch.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Search'**
  String get unnamedSearch;

  /// No description provided for @applySearch.
  ///
  /// In en, this message translates to:
  /// **'Apply Search'**
  String get applySearch;

  /// No description provided for @renameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @verifiedDealerLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified dealer'**
  String get verifiedDealerLabel;

  /// No description provided for @dealerApplicationPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Dealer application pending'**
  String get dealerApplicationPendingLabel;

  /// No description provided for @dealerApplicationDeclinedLabel.
  ///
  /// In en, this message translates to:
  /// **'Dealer application declined'**
  String get dealerApplicationDeclinedLabel;

  /// No description provided for @personalAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Personal account'**
  String get personalAccountLabel;

  /// No description provided for @dealershipLabel.
  ///
  /// In en, this message translates to:
  /// **'Dealership'**
  String get dealershipLabel;

  /// No description provided for @dealerFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Dealer'**
  String get dealerFallbackLabel;

  /// No description provided for @openInGoogleMapsAction.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get openInGoogleMapsAction;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirmMessage;

  /// No description provided for @accountInformationTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Information'**
  String get accountInformationTitle;

  /// No description provided for @termsOfServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfServiceTitle;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// No description provided for @helpHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get helpHowCanWeHelp;

  /// No description provided for @helpBuyingSection.
  ///
  /// In en, this message translates to:
  /// **'Buying'**
  String get helpBuyingSection;

  /// No description provided for @helpSellingSection.
  ///
  /// In en, this message translates to:
  /// **'Selling'**
  String get helpSellingSection;

  /// No description provided for @helpDealersSection.
  ///
  /// In en, this message translates to:
  /// **'Dealers'**
  String get helpDealersSection;

  /// No description provided for @helpPaymentsSection.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get helpPaymentsSection;

  /// No description provided for @helpContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get helpContactSupport;

  /// No description provided for @helpFaqContactSellerQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do I contact a seller?'**
  String get helpFaqContactSellerQuestion;

  /// No description provided for @helpFaqContactSellerAnswer.
  ///
  /// In en, this message translates to:
  /// **'Open a listing and use Call, WhatsApp, or Chat on the detail page.'**
  String get helpFaqContactSellerAnswer;

  /// No description provided for @helpFaqListingsVerifiedQuestion.
  ///
  /// In en, this message translates to:
  /// **'Are listings verified?'**
  String get helpFaqListingsVerifiedQuestion;

  /// No description provided for @helpFaqListingsVerifiedAnswer.
  ///
  /// In en, this message translates to:
  /// **'Dealers with an approved badge are reviewed by our team. Always inspect a vehicle in person before paying.'**
  String get helpFaqListingsVerifiedAnswer;

  /// No description provided for @helpFaqPostListingQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do I post a listing?'**
  String get helpFaqPostListingQuestion;

  /// No description provided for @helpFaqPostListingAnswer.
  ///
  /// In en, this message translates to:
  /// **'Sign in, tap Sell, and follow the steps to add photos, price, and details.'**
  String get helpFaqPostListingAnswer;

  /// No description provided for @helpFaqEditDeleteListingQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do I edit or delete my listing?'**
  String get helpFaqEditDeleteListingQuestion;

  /// No description provided for @helpFaqEditDeleteListingAnswer.
  ///
  /// In en, this message translates to:
  /// **'Open your listing from My Listings or the listing page (owner tools) to edit or delete.'**
  String get helpFaqEditDeleteListingAnswer;

  /// No description provided for @helpFaqRegisterDealerQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do I register as a dealer?'**
  String get helpFaqRegisterDealerQuestion;

  /// No description provided for @helpFaqRegisterDealerAnswer.
  ///
  /// In en, this message translates to:
  /// **'Choose dealer signup and submit your dealership details. Approval may take 1–2 business days.'**
  String get helpFaqRegisterDealerAnswer;

  /// No description provided for @helpFaqPaymentsQuestion.
  ///
  /// In en, this message translates to:
  /// **'Does the app handle payments?'**
  String get helpFaqPaymentsQuestion;

  /// No description provided for @helpFaqPaymentsAnswer.
  ///
  /// In en, this message translates to:
  /// **'Payments are arranged directly between buyer and seller. Never send money before seeing the vehicle.'**
  String get helpFaqPaymentsAnswer;

  /// No description provided for @helpCouldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get helpCouldNotOpenLink;

  /// No description provided for @whatsappAction.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsappAction;

  /// No description provided for @chatSendPhotosVideosTitle.
  ///
  /// In en, this message translates to:
  /// **'Send photos/videos'**
  String get chatSendPhotosVideosTitle;

  /// No description provided for @chatSendPhotosVideosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select multiple images and videos'**
  String get chatSendPhotosVideosSubtitle;

  /// No description provided for @chatSendImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Send image'**
  String get chatSendImageTitle;

  /// No description provided for @chatSendImageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select multiple images'**
  String get chatSendImageSubtitle;

  /// No description provided for @chatSendVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Send video'**
  String get chatSendVideoTitle;

  /// No description provided for @chatSendVideoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select multiple videos'**
  String get chatSendVideoSubtitle;

  /// No description provided for @listingSubmittedPending.
  ///
  /// In en, this message translates to:
  /// **'Your listing is under review and hidden from buyers for now. Track it in My Listings → Pending.'**
  String get listingSubmittedPending;

  /// No description provided for @listingSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your listing is live. Find it in My Listings → Active.'**
  String get listingSubmittedSuccess;

  /// No description provided for @listingPendingBadge.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get listingPendingBadge;

  /// No description provided for @homeOfflineCachedBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Showing cached listings.'**
  String get homeOfflineCachedBanner;

  /// No description provided for @offlineBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Some features may not work.'**
  String get offlineBannerMessage;

  /// No description provided for @myListingsPendingFilter.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get myListingsPendingFilter;

  /// No description provided for @myListingsPendingExplainer.
  ///
  /// In en, this message translates to:
  /// **'These listings are not visible to buyers yet. We review new posts for quality and safety — most are approved quickly.'**
  String get myListingsPendingExplainer;

  /// No description provided for @myListingsNoPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'No pending listings'**
  String get myListingsNoPendingTitle;

  /// No description provided for @myListingsNoPendingHint.
  ///
  /// In en, this message translates to:
  /// **'Listings waiting for review will appear here.'**
  String get myListingsNoPendingHint;

  /// No description provided for @joinAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get joinAnd;

  /// No description provided for @labelPlateType.
  ///
  /// In en, this message translates to:
  /// **'Plate type'**
  String get labelPlateType;

  /// No description provided for @labelPlateCity.
  ///
  /// In en, this message translates to:
  /// **'Plate city'**
  String get labelPlateCity;

  /// No description provided for @plateTypePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get plateTypePrivate;

  /// No description provided for @plateTypeCommercial.
  ///
  /// In en, this message translates to:
  /// **'Commercial'**
  String get plateTypeCommercial;

  /// No description provided for @plateTypeTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get plateTypeTaxi;

  /// No description provided for @plateTypeGovernment.
  ///
  /// In en, this message translates to:
  /// **'Government'**
  String get plateTypeGovernment;

  /// No description provided for @plateTypeTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary'**
  String get plateTypeTemporary;

  /// No description provided for @plateTypeDiplomatic.
  ///
  /// In en, this message translates to:
  /// **'Diplomatic'**
  String get plateTypeDiplomatic;

  /// No description provided for @plateTypePolice.
  ///
  /// In en, this message translates to:
  /// **'Police'**
  String get plateTypePolice;

  /// No description provided for @regionSpecGcc.
  ///
  /// In en, this message translates to:
  /// **'GCC'**
  String get regionSpecGcc;

  /// No description provided for @regionSpecUs.
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get regionSpecUs;

  /// No description provided for @regionSpecIraq.
  ///
  /// In en, this message translates to:
  /// **'Iraq'**
  String get regionSpecIraq;

  /// No description provided for @regionSpecCanada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get regionSpecCanada;

  /// No description provided for @regionSpecEu.
  ///
  /// In en, this message translates to:
  /// **'EU'**
  String get regionSpecEu;

  /// No description provided for @regionSpecCn.
  ///
  /// In en, this message translates to:
  /// **'CN'**
  String get regionSpecCn;

  /// No description provided for @regionSpecKorea.
  ///
  /// In en, this message translates to:
  /// **'Korea'**
  String get regionSpecKorea;

  /// No description provided for @regionSpecRu.
  ///
  /// In en, this message translates to:
  /// **'RU'**
  String get regionSpecRu;

  /// No description provided for @regionSpecIran.
  ///
  /// In en, this message translates to:
  /// **'Iran'**
  String get regionSpecIran;

  /// No description provided for @vinCopied.
  ///
  /// In en, this message translates to:
  /// **'VIN copied'**
  String get vinCopied;

  /// No description provided for @sellStep1Photos.
  ///
  /// In en, this message translates to:
  /// **'Step 1: Photos'**
  String get sellStep1Photos;

  /// No description provided for @sellStep2BasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Step 2: Basic info'**
  String get sellStep2BasicInfo;

  /// No description provided for @sellStep3Details.
  ///
  /// In en, this message translates to:
  /// **'Step 3: Details'**
  String get sellStep3Details;

  /// No description provided for @sellStep4Pricing.
  ///
  /// In en, this message translates to:
  /// **'Step 4: Pricing'**
  String get sellStep4Pricing;

  /// No description provided for @sellStep5Plates.
  ///
  /// In en, this message translates to:
  /// **'Step 5: Plates'**
  String get sellStep5Plates;

  /// No description provided for @sellStep6Review.
  ///
  /// In en, this message translates to:
  /// **'Step 6: Review'**
  String get sellStep6Review;

  /// No description provided for @seats.
  ///
  /// In en, this message translates to:
  /// **'seats'**
  String get seats;

  /// No description provided for @labelCylinders.
  ///
  /// In en, this message translates to:
  /// **'cylinders'**
  String get labelCylinders;

  /// No description provided for @labelDealership.
  ///
  /// In en, this message translates to:
  /// **'Dealership'**
  String get labelDealership;

  /// No description provided for @labelPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get labelPhone;

  /// No description provided for @labelLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get labelLocation;

  /// No description provided for @pleaseSelectAtLeastOnePhoto.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one photo'**
  String get pleaseSelectAtLeastOnePhoto;

  /// No description provided for @couldNotLoadListings.
  ///
  /// In en, this message translates to:
  /// **'Could not load listings'**
  String get couldNotLoadListings;

  /// No description provided for @homeFeedLoadingListings.
  ///
  /// In en, this message translates to:
  /// **'Loading listings...'**
  String get homeFeedLoadingListings;

  /// No description provided for @homeFeedSortingListings.
  ///
  /// In en, this message translates to:
  /// **'Sorting listings...'**
  String get homeFeedSortingListings;

  /// No description provided for @homeFeedCachedResultsBanner.
  ///
  /// In en, this message translates to:
  /// **'Showing cached results'**
  String get homeFeedCachedResultsBanner;

  /// No description provided for @homeFeedSortedLocally.
  ///
  /// In en, this message translates to:
  /// **'Sorted locally (server unavailable)'**
  String get homeFeedSortedLocally;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @homeFeedSortDisabled.
  ///
  /// In en, this message translates to:
  /// **'Sorting temporarily disabled due to server issue'**
  String get homeFeedSortDisabled;

  /// No description provided for @homeFeedNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and try again.'**
  String get homeFeedNetworkError;

  /// Parameterized home feed server error
  ///
  /// In en, this message translates to:
  /// **'Server error ({statusCode}). Please try again later.'**
  String homeFeedServerError(String statusCode);

  /// No description provided for @acceptTermsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms and Privacy Policy'**
  String get acceptTermsRequired;

  /// No description provided for @videoPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play this video.'**
  String get videoPlaybackFailed;

  /// No description provided for @photosUploaded.
  ///
  /// In en, this message translates to:
  /// **'Photos uploaded'**
  String get photosUploaded;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @missingDealerId.
  ///
  /// In en, this message translates to:
  /// **'Missing dealer id'**
  String get missingDealerId;

  /// No description provided for @markAsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Mark as available'**
  String get markAsAvailable;

  /// No description provided for @markAsSold.
  ///
  /// In en, this message translates to:
  /// **'Mark as sold'**
  String get markAsSold;

  /// No description provided for @reportListing.
  ///
  /// In en, this message translates to:
  /// **'Report listing'**
  String get reportListing;

  /// No description provided for @reportSeller.
  ///
  /// In en, this message translates to:
  /// **'Report seller'**
  String get reportSeller;

  /// No description provided for @unableToSelectThatPhoto.
  ///
  /// In en, this message translates to:
  /// **'Unable to select that photo.'**
  String get unableToSelectThatPhoto;

  /// No description provided for @pleaseUploadAClearPhotoOfYourBusiness.
  ///
  /// In en, this message translates to:
  /// **'Please upload a clear photo of your business.'**
  String get pleaseUploadAClearPhotoOfYourBusiness;

  /// No description provided for @dealershipDetailsSubmittedYourApplicationIsPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Dealership details submitted. Your application is pending review.'**
  String get dealershipDetailsSubmittedYourApplicationIsPendingReview;

  /// No description provided for @addAPhotoThatHelpsUsVerifyThisDealership.
  ///
  /// In en, this message translates to:
  /// **'Add a photo that helps us verify this dealership'**
  String get addAPhotoThatHelpsUsVerifyThisDealership;

  /// No description provided for @privateDealershipPhotoUploaded.
  ///
  /// In en, this message translates to:
  /// **'Private dealership photo uploaded'**
  String get privateDealershipPhotoUploaded;

  /// No description provided for @createDealershipAccount.
  ///
  /// In en, this message translates to:
  /// **'Create dealership account'**
  String get createDealershipAccount;

  /// No description provided for @finalSetupStep.
  ///
  /// In en, this message translates to:
  /// **'Final setup step'**
  String get finalSetupStep;

  /// No description provided for @buildYourDealershipPresence.
  ///
  /// In en, this message translates to:
  /// **'Build your dealership presence'**
  String get buildYourDealershipPresence;

  /// No description provided for @addAccurateBusinessDetailsSoBuyersCanTrustAndContactYourDealership.
  ///
  /// In en, this message translates to:
  /// **'Add accurate business details so buyers can trust and contact your dealership.'**
  String get addAccurateBusinessDetailsSoBuyersCanTrustAndContactYourDealership;

  /// No description provided for @reviewUsuallyTakes12BusinessDays.
  ///
  /// In en, this message translates to:
  /// **'Review usually takes 1–2 business days'**
  String get reviewUsuallyTakes12BusinessDays;

  /// No description provided for @changesRequested.
  ///
  /// In en, this message translates to:
  /// **'Changes requested'**
  String get changesRequested;

  /// No description provided for @businessInformation.
  ///
  /// In en, this message translates to:
  /// **'Business information'**
  String get businessInformation;

  /// No description provided for @theseDetailsWillAppearOnYourPublicDealershipProfile.
  ///
  /// In en, this message translates to:
  /// **'These details will appear on your public dealership profile.'**
  String get theseDetailsWillAppearOnYourPublicDealershipProfile;

  /// No description provided for @dealershipName.
  ///
  /// In en, this message translates to:
  /// **'Dealership name'**
  String get dealershipName;

  /// No description provided for @yourRegisteredOrTradingName.
  ///
  /// In en, this message translates to:
  /// **'Your registered or trading name'**
  String get yourRegisteredOrTradingName;

  /// No description provided for @businessPhone.
  ///
  /// In en, this message translates to:
  /// **'Business phone'**
  String get businessPhone;

  /// No description provided for @aNumberBuyersCanReach.
  ///
  /// In en, this message translates to:
  /// **'A number buyers can reach'**
  String get aNumberBuyersCanReach;

  /// No description provided for @dealershipLocation.
  ///
  /// In en, this message translates to:
  /// **'Dealership location'**
  String get dealershipLocation;

  /// No description provided for @cityDistrictAndStreet.
  ///
  /// In en, this message translates to:
  /// **'City, district, and street'**
  String get cityDistrictAndStreet;

  /// No description provided for @aboutYourDealershipOptional.
  ///
  /// In en, this message translates to:
  /// **'About your dealership (optional)'**
  String get aboutYourDealershipOptional;

  /// No description provided for @describeYourInventoryExperienceAndCustomerService.
  ///
  /// In en, this message translates to:
  /// **'Describe your inventory, experience, and customer service'**
  String get describeYourInventoryExperienceAndCustomerService;

  /// No description provided for @dealershipVerificationPhoto.
  ///
  /// In en, this message translates to:
  /// **'Dealership verification photo'**
  String get dealershipVerificationPhoto;

  /// No description provided for @requiredUsedPrivatelyByOurReviewTeamAndNeverShownOnYourPublicProfile.
  ///
  /// In en, this message translates to:
  /// **'Required · Used privately by our review team and never shown on your public profile.'**
  String
  get requiredUsedPrivatelyByOurReviewTeamAndNeverShownOnYourPublicProfile;

  /// No description provided for @chooseVerificationPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose verification photo'**
  String get chooseVerificationPhoto;

  /// No description provided for @replacePhoto.
  ///
  /// In en, this message translates to:
  /// **'Replace photo'**
  String get replacePhoto;

  /// No description provided for @uploadOneClearRecentPhotoOfTheDealershipStorefrontCarsForSaleShowroomOrO.
  ///
  /// In en, this message translates to:
  /// **'Upload one clear, recent photo of the dealership storefront, cars for sale, showroom, or office—anything that helps our team confirm the business is genuine.'**
  String
  get uploadOneClearRecentPhotoOfTheDealershipStorefrontCarsForSaleShowroomOrO;

  /// No description provided for @submitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get submitting;

  /// No description provided for @submitForReview.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get submitForReview;

  /// No description provided for @yourBusinessInformationIsHandledSecurely.
  ///
  /// In en, this message translates to:
  /// **'Your business information is handled securely.'**
  String get yourBusinessInformationIsHandledSecurely;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Check Your Email'**
  String get checkYourEmail;

  /// No description provided for @checkYourMessages.
  ///
  /// In en, this message translates to:
  /// **'Check your messages'**
  String get checkYourMessages;

  /// No description provided for @enterTheEmailAddressForYourAccountWeWillSendAResetCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the email address for your account. We will send a reset code.'**
  String get enterTheEmailAddressForYourAccountWeWillSendAResetCode;

  /// No description provided for @enterThePhoneNumberForYourAccountWeWillSendAResetCodeBySMS.
  ///
  /// In en, this message translates to:
  /// **'Enter the phone number for your account. We will send a reset code by SMS.'**
  String get enterThePhoneNumberForYourAccountWeWillSendAResetCodeBySMS;

  /// Migrated legacy string (weVeSentAPasswordResetLinkToEmailPleaseCheckYourEmailAndFollowTheInstruc)
  ///
  /// In en, this message translates to:
  /// **'We\'ve sent a password reset link to {email}. Please check your email and follow the instructions.'**
  String
  weVeSentAPasswordResetLinkToEmailPleaseCheckYourEmailAndFollowTheInstruc(
    String email,
  );

  /// Migrated legacy string (ifAnAccountExistsForPhoneWeSentAPasswordResetCodeBySMS)
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {phone}, we sent a password reset code by SMS.'**
  String ifAnAccountExistsForPhoneWeSentAPasswordResetCodeBySMS(String phone);

  /// No description provided for @ifYouDonTSeeItCheckYourSpamOrJunkFolderTheLinkIsOnlySentIfAnAccountExist.
  ///
  /// In en, this message translates to:
  /// **'If you don\'t see it, check your spam or junk folder. The link is only sent if an account exists for this email.'**
  String
  get ifYouDonTSeeItCheckYourSpamOrJunkFolderTheLinkIsOnlySentIfAnAccountExist;

  /// No description provided for @smsMayTakeAMinuteOrTwoACodeIsOnlySentIfAnAccountExistsForThisNumber.
  ///
  /// In en, this message translates to:
  /// **'SMS may take a minute or two. A code is only sent if an account exists for this number.'**
  String
  get smsMayTakeAMinuteOrTwoACodeIsOnlySentIfAnAccountExistsForThisNumber;

  /// No description provided for @pleaseEnterAValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get pleaseEnterAValidEmail;

  /// No description provided for @pleaseEnterAValidPhoneNumberAtLeast8Digits.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number (at least 8 digits)'**
  String get pleaseEnterAValidPhoneNumberAtLeast8Digits;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLink;

  /// No description provided for @sendResetCodeSMS.
  ///
  /// In en, this message translates to:
  /// **'Send reset code (SMS)'**
  String get sendResetCodeSMS;

  /// No description provided for @iHaveTheCodeSetNewPassword.
  ///
  /// In en, this message translates to:
  /// **'I have the code – set new password'**
  String get iHaveTheCodeSetNewPassword;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get backToLogin;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @tooManyResetAttemptsPleaseWaitALittleAndTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Too many reset attempts. Please wait a little and try again.'**
  String get tooManyResetAttemptsPleaseWaitALittleAndTryAgain;

  /// No description provided for @failedToSendResetLinkCheckYourEmailAndTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset link. Check your email and try again later.'**
  String get failedToSendResetLinkCheckYourEmailAndTryAgainLater;

  /// No description provided for @failedToSendSMSCheckTheNumberAndTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Failed to send SMS. Check the number and try again later.'**
  String get failedToSendSMSCheckTheNumberAndTryAgainLater;

  /// No description provided for @thisPhoneNumberIsRegisteredToAPersonalAccountPleaseUsePersonalLoginInste.
  ///
  /// In en, this message translates to:
  /// **'This phone number is registered to a personal account. Please use personal login instead.'**
  String
  get thisPhoneNumberIsRegisteredToAPersonalAccountPleaseUsePersonalLoginInste;

  /// No description provided for @thisPhoneNumberIsRegisteredToADealerAccountPleaseUseDealerLoginInstead.
  ///
  /// In en, this message translates to:
  /// **'This phone number is registered to a dealer account. Please use dealer login instead.'**
  String
  get thisPhoneNumberIsRegisteredToADealerAccountPleaseUseDealerLoginInstead;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @onboardingBrowseTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse listings'**
  String get onboardingBrowseTitle;

  /// No description provided for @onboardingBrowseBody.
  ///
  /// In en, this message translates to:
  /// **'Search and filter cars near you. Open any listing for photos, specs, and seller chat.'**
  String get onboardingBrowseBody;

  /// No description provided for @onboardingFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Save favorites'**
  String get onboardingFavoritesTitle;

  /// No description provided for @onboardingFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on a listing — find everything again from Home or Profile.'**
  String get onboardingFavoritesBody;

  /// No description provided for @onboardingSellTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell your car'**
  String get onboardingSellTitle;

  /// No description provided for @onboardingSellBody.
  ///
  /// In en, this message translates to:
  /// **'Use Sell in the bottom bar to list a car in a few guided steps.'**
  String get onboardingSellBody;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @enterYourPhoneNumberToLogInOrCreateAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number to log in or create an account.'**
  String get enterYourPhoneNumberToLogInOrCreateAnAccount;

  /// No description provided for @accountType.
  ///
  /// In en, this message translates to:
  /// **'Account type'**
  String get accountType;

  /// No description provided for @dealerApplicationNeedsChanges.
  ///
  /// In en, this message translates to:
  /// **'Dealer application needs changes'**
  String get dealerApplicationNeedsChanges;

  /// No description provided for @recentlyViewed.
  ///
  /// In en, this message translates to:
  /// **'Recently viewed'**
  String get recentlyViewed;

  /// No description provided for @editDealerPage.
  ///
  /// In en, this message translates to:
  /// **'Edit dealer page'**
  String get editDealerPage;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @signInToAccessYourProfileFeatures.
  ///
  /// In en, this message translates to:
  /// **'Sign in to access your profile features.'**
  String get signInToAccessYourProfileFeatures;

  /// No description provided for @iAgreeToThe.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get iAgreeToThe;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get terms;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @searchAppliedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Search applied successfully!'**
  String get searchAppliedSuccessfully;

  /// No description provided for @appliedFilters.
  ///
  /// In en, this message translates to:
  /// **'Applied Filters:'**
  String get appliedFilters;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @owners.
  ///
  /// In en, this message translates to:
  /// **'Owners'**
  String get owners;

  /// No description provided for @accidentHistory.
  ///
  /// In en, this message translates to:
  /// **'Accident History'**
  String get accidentHistory;

  /// No description provided for @deleteSavedSearch.
  ///
  /// In en, this message translates to:
  /// **'Delete saved search?'**
  String get deleteSavedSearch;

  /// No description provided for @thisWillPermanentlyRemoveThisSavedSearchThisCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove this saved search. This cannot be undone.'**
  String get thisWillPermanentlyRemoveThisSavedSearchThisCannotBeUndone;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'FEATURED'**
  String get featured;

  /// No description provided for @less.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get less;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @selectFromList.
  ///
  /// In en, this message translates to:
  /// **'Select from list'**
  String get selectFromList;

  /// No description provided for @searchMakeOrModel.
  ///
  /// In en, this message translates to:
  /// **'Search make or model'**
  String get searchMakeOrModel;

  /// No description provided for @noMakesOrModelsMatchYourSearch.
  ///
  /// In en, this message translates to:
  /// **'No makes or models match your search.'**
  String get noMakesOrModelsMatchYourSearch;

  /// No description provided for @make.
  ///
  /// In en, this message translates to:
  /// **'Make'**
  String get make;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// Migrated legacy string (filterSelectedCount)
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String filterSelectedCount(String count);

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @youLlBeNotifiedWhenAMatchingCarIsListed.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be notified when a matching car is listed'**
  String get youLlBeNotifiedWhenAMatchingCarIsListed;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @searchBrandsModels.
  ///
  /// In en, this message translates to:
  /// **'Search brands & models'**
  String get searchBrandsModels;

  /// No description provided for @showCars.
  ///
  /// In en, this message translates to:
  /// **'Show Cars'**
  String get showCars;

  /// No description provided for @searchCars.
  ///
  /// In en, this message translates to:
  /// **'Search Cars'**
  String get searchCars;

  /// No description provided for @saveSearch.
  ///
  /// In en, this message translates to:
  /// **'Save search'**
  String get saveSearch;

  /// No description provided for @notifyMe.
  ///
  /// In en, this message translates to:
  /// **'Notify me'**
  String get notifyMe;

  /// No description provided for @featuredListings.
  ///
  /// In en, this message translates to:
  /// **'Featured Listings'**
  String get featuredListings;

  /// No description provided for @plate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get plate;

  /// No description provided for @viewDescription.
  ///
  /// In en, this message translates to:
  /// **'View description'**
  String get viewDescription;

  /// No description provided for @licensePlates.
  ///
  /// In en, this message translates to:
  /// **'License plates'**
  String get licensePlates;

  /// No description provided for @draftInProgress.
  ///
  /// In en, this message translates to:
  /// **'Draft in progress'**
  String get draftInProgress;

  /// No description provided for @discardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard draft?'**
  String get discardDraft;

  /// No description provided for @thisWillPermanentlyDeleteThisDraftListingThisCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete this draft listing. This cannot be undone.'**
  String get thisWillPermanentlyDeleteThisDraftListingThisCannotBeUndone;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @failedToBlurPlatesPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Failed to blur plates. Please try again.'**
  String get failedToBlurPlatesPleaseTryAgain;

  /// No description provided for @platesBlurredSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Plates blurred successfully.'**
  String get platesBlurredSuccessfully;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @draftsInProgress.
  ///
  /// In en, this message translates to:
  /// **'Drafts in progress'**
  String get draftsInProgress;

  /// No description provided for @continueAnyDraftDiscardOneOrStartANewListingWhileKeepingTheOthers.
  ///
  /// In en, this message translates to:
  /// **'Continue any draft, discard one, or start a new listing while keeping the others.'**
  String get continueAnyDraftDiscardOneOrStartANewListingWhileKeepingTheOthers;

  /// No description provided for @startNewListing.
  ///
  /// In en, this message translates to:
  /// **'Start new listing'**
  String get startNewListing;

  /// No description provided for @startANewListing.
  ///
  /// In en, this message translates to:
  /// **'Start a new listing'**
  String get startANewListing;

  /// No description provided for @noDraftsYetCreateYourFirstCarListingToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'No drafts yet. Create your first car listing to get started.'**
  String get noDraftsYetCreateYourFirstCarListingToGetStarted;

  /// No description provided for @specsAppliedYearSetStep2FieldsPreFilled.
  ///
  /// In en, this message translates to:
  /// **'Specs applied — year set; step 2 fields pre-filled.'**
  String get specsAppliedYearSetStep2FieldsPreFilled;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get search;

  /// No description provided for @loadingVehicleSpecs.
  ///
  /// In en, this message translates to:
  /// **'Loading vehicle specs…'**
  String get loadingVehicleSpecs;

  /// No description provided for @specDatabaseUnavailableRestartTheAppAfterFlutterPubGet.
  ///
  /// In en, this message translates to:
  /// **'Spec database unavailable. Restart the app after flutter pub get.'**
  String get specDatabaseUnavailableRestartTheAppAfterFlutterPubGet;

  /// No description provided for @catalogAutoFill.
  ///
  /// In en, this message translates to:
  /// **'Catalog auto-fill'**
  String get catalogAutoFill;

  /// No description provided for @selectAModelYearToLoadMatchingSpecs.
  ///
  /// In en, this message translates to:
  /// **'Select a model year to load matching specs.'**
  String get selectAModelYearToLoadMatchingSpecs;

  /// No description provided for @modelYear.
  ///
  /// In en, this message translates to:
  /// **'Model year'**
  String get modelYear;

  /// No description provided for @youCanChangeTheseInStep2.
  ///
  /// In en, this message translates to:
  /// **'You can change these in step 2.'**
  String get youCanChangeTheseInStep2;

  /// No description provided for @specsAvailableForThisYear.
  ///
  /// In en, this message translates to:
  /// **'Specs available for this year.'**
  String get specsAvailableForThisYear;

  /// No description provided for @applySpecs.
  ///
  /// In en, this message translates to:
  /// **'Apply specs'**
  String get applySpecs;

  /// No description provided for @specifications.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get specifications;

  /// No description provided for @vinOptional.
  ///
  /// In en, this message translates to:
  /// **'VIN (optional)'**
  String get vinOptional;

  /// No description provided for @vinMustBe17Characters.
  ///
  /// In en, this message translates to:
  /// **'VIN must be 17 characters'**
  String get vinMustBe17Characters;

  /// No description provided for @setYourPriceAndContactInformation.
  ///
  /// In en, this message translates to:
  /// **'Set your price and contact information'**
  String get setYourPriceAndContactInformation;

  /// No description provided for @whatsappPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp/Phone Number'**
  String get whatsappPhoneNumber;

  /// No description provided for @whatsappPhoneNumber2.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp/Phone Number *'**
  String get whatsappPhoneNumber2;

  /// No description provided for @listingContactPhonesTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact phone numbers'**
  String get listingContactPhonesTitle;

  /// No description provided for @listingContactPhonesHint.
  ///
  /// In en, this message translates to:
  /// **'Add up to 3 numbers. Verify each with a code. You can remove your default number after verifying another.'**
  String get listingContactPhonesHint;

  /// No description provided for @addPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Add phone number'**
  String get addPhoneNumber;

  /// No description provided for @listingContactPhoneN.
  ///
  /// In en, this message translates to:
  /// **'Phone {n}'**
  String listingContactPhoneN(int n);

  /// No description provided for @phoneVerifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get phoneVerifiedBadge;

  /// No description provided for @verifyContactPhonesBeforeContinuing.
  ///
  /// In en, this message translates to:
  /// **'Verify each contact phone with a code before continuing.'**
  String get verifyContactPhonesBeforeContinuing;

  /// No description provided for @duplicateContactPhoneError.
  ///
  /// In en, this message translates to:
  /// **'This phone number is already added.'**
  String get duplicateContactPhoneError;

  /// No description provided for @pleaseEnterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone number'**
  String get pleaseEnterPhoneNumber;

  /// No description provided for @pleaseEnterAValidPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number'**
  String get pleaseEnterAValidPhoneNumber;

  /// No description provided for @addDetailsAboutTheCarConditionFeaturesOrNotes.
  ///
  /// In en, this message translates to:
  /// **'Add details about the car, condition, features, or notes'**
  String get addDetailsAboutTheCarConditionFeaturesOrNotes;

  /// Migrated legacy string (priceSelectedCurrencyOptional)
  ///
  /// In en, this message translates to:
  /// **'Price ({selectedCurrency}) (optional)'**
  String priceSelectedCurrencyOptional(String selectedCurrency);

  /// No description provided for @enterPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter price'**
  String get enterPrice;

  /// No description provided for @invalidPrice.
  ///
  /// In en, this message translates to:
  /// **'Invalid price'**
  String get invalidPrice;

  /// No description provided for @priceCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Price cannot be negative'**
  String get priceCannotBeNegative;

  /// No description provided for @damageCrashPhotos.
  ///
  /// In en, this message translates to:
  /// **'Damage / crash photos'**
  String get damageCrashPhotos;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @tapTheStarOnAPhotoToSetItAsTheCoverImageShownFirstInYourListing.
  ///
  /// In en, this message translates to:
  /// **'Tap the star on a photo to set it as the cover image shown first in your listing.'**
  String get tapTheStarOnAPhotoToSetItAsTheCoverImageShownFirstInYourListing;

  /// No description provided for @cover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get cover;

  /// No description provided for @blurringLicensePlatesInTheBackground.
  ///
  /// In en, this message translates to:
  /// **'Blurring license plates in the background…'**
  String get blurringLicensePlatesInTheBackground;

  /// No description provided for @plateBlurReadyYouCanChooseLater.
  ///
  /// In en, this message translates to:
  /// **'Plate blur ready — you can choose later'**
  String get plateBlurReadyYouCanChooseLater;

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videos;

  /// No description provided for @addMoreVideos.
  ///
  /// In en, this message translates to:
  /// **'Add More Videos'**
  String get addMoreVideos;

  /// No description provided for @addVideos.
  ///
  /// In en, this message translates to:
  /// **'Add Videos'**
  String get addVideos;

  /// No description provided for @stillBlurringPlatesInTheBackgroundPhotosWillAppearHereWhenReady.
  ///
  /// In en, this message translates to:
  /// **'Still blurring plates in the background. Photos will appear here when ready.'**
  String get stillBlurringPlatesInTheBackgroundPhotosWillAppearHereWhenReady;

  /// No description provided for @blurredPhotos.
  ///
  /// In en, this message translates to:
  /// **'Blurred photos'**
  String get blurredPhotos;

  /// No description provided for @blurredDamagePhotos.
  ///
  /// In en, this message translates to:
  /// **'Blurred damage photos'**
  String get blurredDamagePhotos;

  /// No description provided for @noPhotosAvailable.
  ///
  /// In en, this message translates to:
  /// **'No photos available.'**
  String get noPhotosAvailable;

  /// No description provided for @blurredPhotosAreNotReadyYet.
  ///
  /// In en, this message translates to:
  /// **'Blurred photos are not ready yet.'**
  String get blurredPhotosAreNotReadyYet;

  /// No description provided for @blurPlatesNow.
  ///
  /// In en, this message translates to:
  /// **'Blur plates now'**
  String get blurPlatesNow;

  /// No description provided for @originalPhotos.
  ///
  /// In en, this message translates to:
  /// **'Original photos'**
  String get originalPhotos;

  /// No description provided for @originalDamagePhotos.
  ///
  /// In en, this message translates to:
  /// **'Original damage photos'**
  String get originalDamagePhotos;

  /// No description provided for @chooseWhetherToPublishPhotosWithBlurredPlates.
  ///
  /// In en, this message translates to:
  /// **'Choose whether to publish photos with blurred plates'**
  String get chooseWhetherToPublishPhotosWithBlurredPlates;

  /// No description provided for @blurPlates.
  ///
  /// In en, this message translates to:
  /// **'Blur plates?'**
  String get blurPlates;

  /// No description provided for @yesBlurPlates.
  ///
  /// In en, this message translates to:
  /// **'Yes, blur plates'**
  String get yesBlurPlates;

  /// No description provided for @noKeepOriginal.
  ///
  /// In en, this message translates to:
  /// **'No, keep original'**
  String get noKeepOriginal;

  /// No description provided for @yesUseBlurredPhotos.
  ///
  /// In en, this message translates to:
  /// **'Yes, use blurred photos'**
  String get yesUseBlurredPhotos;

  /// No description provided for @hideLicensePlatesOnYourListing.
  ///
  /// In en, this message translates to:
  /// **'Hide license plates on your listing'**
  String get hideLicensePlatesOnYourListing;

  /// No description provided for @noKeepOriginalPhotos.
  ///
  /// In en, this message translates to:
  /// **'No, keep original photos'**
  String get noKeepOriginalPhotos;

  /// No description provided for @publishThePhotosExactlyAsYouUploadedThem.
  ///
  /// In en, this message translates to:
  /// **'Publish the photos exactly as you uploaded them'**
  String get publishThePhotosExactlyAsYouUploadedThem;

  /// No description provided for @pleaseChooseWhetherToBlurPlates.
  ///
  /// In en, this message translates to:
  /// **'Please choose whether to blur plates'**
  String get pleaseChooseWhetherToBlurPlates;

  /// No description provided for @pleaseWaitForPlateBlurringToFinish.
  ///
  /// In en, this message translates to:
  /// **'Please wait for plate blurring to finish'**
  String get pleaseWaitForPlateBlurringToFinish;

  /// No description provided for @blurPlatesFirstOrChooseToKeepOriginals.
  ///
  /// In en, this message translates to:
  /// **'Blur plates first, or choose to keep originals'**
  String get blurPlatesFirstOrChooseToKeepOriginals;

  /// No description provided for @callSeller.
  ///
  /// In en, this message translates to:
  /// **'Call Seller'**
  String get callSeller;

  /// No description provided for @privateSeller.
  ///
  /// In en, this message translates to:
  /// **'Private seller'**
  String get privateSeller;

  /// No description provided for @dealer.
  ///
  /// In en, this message translates to:
  /// **'Dealer'**
  String get dealer;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @tapToOpenDealershipPage.
  ///
  /// In en, this message translates to:
  /// **'Tap to open dealership page'**
  String get tapToOpenDealershipPage;

  /// No description provided for @cannotAddToComparison.
  ///
  /// In en, this message translates to:
  /// **'Cannot add to comparison'**
  String get cannotAddToComparison;

  /// No description provided for @dealershipLogo.
  ///
  /// In en, this message translates to:
  /// **'Dealership logo'**
  String get dealershipLogo;

  /// No description provided for @coverImage.
  ///
  /// In en, this message translates to:
  /// **'Cover image'**
  String get coverImage;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening hours'**
  String get openingHours;

  /// No description provided for @youCanAlsoReviewYourContactDetailsLocationDescriptionAndMapPin.
  ///
  /// In en, this message translates to:
  /// **'You can also review your contact details, location, description, and map pin.'**
  String get youCanAlsoReviewYourContactDetailsLocationDescriptionAndMapPin;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @completeProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete profile'**
  String get completeProfile;

  /// No description provided for @searchByBrand.
  ///
  /// In en, this message translates to:
  /// **'Search by Brand'**
  String get searchByBrand;

  /// No description provided for @searchByModel.
  ///
  /// In en, this message translates to:
  /// **'Search by Model'**
  String get searchByModel;

  /// No description provided for @searchBrands.
  ///
  /// In en, this message translates to:
  /// **'Search brands...'**
  String get searchBrands;

  /// No description provided for @searchModels.
  ///
  /// In en, this message translates to:
  /// **'Search models...'**
  String get searchModels;

  /// No description provided for @listingMarkedAsSold.
  ///
  /// In en, this message translates to:
  /// **'Listing marked as sold'**
  String get listingMarkedAsSold;

  /// No description provided for @listingIsAvailableAgain.
  ///
  /// In en, this message translates to:
  /// **'Listing is available again'**
  String get listingIsAvailableAgain;

  /// No description provided for @setUpYourDealerPage.
  ///
  /// In en, this message translates to:
  /// **'Set up your dealer page'**
  String get setUpYourDealerPage;

  /// No description provided for @yourDealershipIsApproved.
  ///
  /// In en, this message translates to:
  /// **'Your dealership is approved!'**
  String get yourDealershipIsApproved;

  /// No description provided for @yourDealershipIsApprovedFillInTheInformationOnThisPageToFinishSettingUpT.
  ///
  /// In en, this message translates to:
  /// **'Your dealership is approved. Fill in the information on this page to finish setting up the dealer page buyers will see.'**
  String
  get yourDealershipIsApprovedFillInTheInformationOnThisPageToFinishSettingUpT;

  /// No description provided for @completeYourPublicDealerPageSoBuyersCanRecognizeYourBusinessAndKnowWhenT.
  ///
  /// In en, this message translates to:
  /// **'Complete your public dealer page so buyers can recognize your business and know when to contact you.'**
  String
  get completeYourPublicDealerPageSoBuyersCanRecognizeYourBusinessAndKnowWhenT;

  /// No description provided for @switchToUSD.
  ///
  /// In en, this message translates to:
  /// **'Switch to USD'**
  String get switchToUSD;

  /// No description provided for @switchToIQD.
  ///
  /// In en, this message translates to:
  /// **'Switch to IQD'**
  String get switchToIQD;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @changeProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get changeProfilePhoto;

  /// No description provided for @playVideo.
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get playVideo;

  /// No description provided for @pauseVideo.
  ///
  /// In en, this message translates to:
  /// **'Pause video'**
  String get pauseVideo;
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
