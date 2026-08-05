// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CarNet';

  @override
  String get navHome => 'Home';

  @override
  String get navAdd => 'Add';

  @override
  String get navChat => 'Chat';

  @override
  String get navSaved => 'Saved';

  @override
  String get navDealers => 'Dealerships';

  @override
  String get navLogin => 'Login';

  @override
  String get navProfile => 'Profile';

  @override
  String get addListingTitle => 'Add Listing';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get chatTitle => 'Chat';

  @override
  String get loginTitle => 'Login';

  @override
  String get signupTitle => 'Sign Up';

  @override
  String get profileTitle => 'Profile';

  @override
  String get homeSearchHeading => 'Search';

  @override
  String get chatConversationTitle => 'Chat Conversation';

  @override
  String get editListingTitle => 'Edit Listing';

  @override
  String get brandLabel => 'Brand';

  @override
  String get anyBrand => 'Any Brand';

  @override
  String get modelLabel => 'Model';

  @override
  String get anyModel => 'Any Model';

  @override
  String get yearLabel => 'Year';

  @override
  String get anyYear => 'Any Year';

  @override
  String get priceLabel => 'Price';

  @override
  String get anyPrice => 'Any Price';

  @override
  String get mileageLabel => 'Mileage';

  @override
  String get anyMileage => 'Any Mileage';

  @override
  String get conditionLabel => 'Condition';

  @override
  String get anyCondition => 'Any';

  @override
  String get transmissionLabel => 'Transmission';

  @override
  String get fuelTypeLabel => 'Fuel Type';

  @override
  String get bodyTypeLabel => 'Body Type';

  @override
  String get cityLabel => 'City';

  @override
  String get allCities => 'All cities';

  @override
  String get applyFilters => 'Apply Filters';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get submit => 'Submit';

  @override
  String get ok => 'OK';

  @override
  String get any => 'Any';

  @override
  String get activeFilters => 'Active Filters:';

  @override
  String get moreFilters => 'More Filters';

  @override
  String get priceRange => 'Price Range';

  @override
  String get minPrice => 'Min Price';

  @override
  String get maxPrice => 'Max Price';

  @override
  String get anyMinPrice => 'Any Min Price';

  @override
  String get anyMaxPrice => 'Any Max Price';

  @override
  String get yearRange => 'Year Range';

  @override
  String get minYear => 'Min Year';

  @override
  String get maxYear => 'Max Year';

  @override
  String get anyMinYear => 'Any Min Year';

  @override
  String get anyMaxYear => 'Any Max Year';

  @override
  String get enterMinYear => 'Enter min year';

  @override
  String get enterMaxYear => 'Enter max year';

  @override
  String get mileageRange => 'Mileage Range';

  @override
  String get minMileage => 'Min Mileage';

  @override
  String get maxMileage => 'Max Mileage';

  @override
  String get enterMinMileage => 'Enter min mileage';

  @override
  String get enterMaxMileage => 'Enter max mileage';

  @override
  String get titleStatus => 'Title Status';

  @override
  String get damagedParts => 'Damaged Parts';

  @override
  String get selectBodyType => 'Select Body Type';

  @override
  String get colorLabel => 'Color';

  @override
  String get selectColor => 'Select Color';

  @override
  String get driveType => 'Drive Type';

  @override
  String get regionSpecsLabel => 'Region specs';

  @override
  String get cylinderCount => 'Cylinder Count';

  @override
  String get seating => 'Seating';

  @override
  String get engineSizeL => 'Engine Size (L)';

  @override
  String get sortBy => 'Sort By';

  @override
  String get selectBrand => 'Select Brand';

  @override
  String get tapToSelectBrand => 'Tap to select a brand';

  @override
  String get trimLabel => 'Trim';

  @override
  String get loginRequired => 'Login Required';

  @override
  String get authenticationRequired => 'Authentication Required';

  @override
  String get requiredField => 'Required';

  @override
  String get sendCodeFirst => 'Send code first';

  @override
  String get resend => 'Resend';

  @override
  String get sendCode => 'Send code';

  @override
  String get typeMessage => 'Type a message';

  @override
  String get error => 'Error';

  @override
  String get enterPhoneNumber => 'Enter phone number';

  @override
  String get submitListing => 'Submit Listing';

  @override
  String get specificationsLabel => 'Specifications';

  @override
  String get detail_condition => 'Condition';

  @override
  String get detail_fuel => 'Fuel';

  @override
  String get detail_body => 'Body';

  @override
  String get detail_color => 'Color';

  @override
  String get detail_drive => 'Drive';

  @override
  String get detail_cylinders => 'Cylinders';

  @override
  String get detail_engine => 'Engine';

  @override
  String get detail_seating => 'Seating';

  @override
  String get value_condition_new => 'New';

  @override
  String get value_condition_used => 'Used';

  @override
  String get value_transmission_automatic => 'Automatic';

  @override
  String get value_transmission_manual => 'Manual';

  @override
  String get value_fuel_gasoline => 'Gasoline';

  @override
  String get value_fuel_diesel => 'Diesel';

  @override
  String get value_fuel_electric => 'Electric';

  @override
  String get value_fuel_hybrid => 'Hybrid';

  @override
  String get value_fuel_lpg => 'LPG';

  @override
  String get value_fuel_plugin_hybrid => 'Plug-in Hybrid';

  @override
  String get value_title_clean => 'Clean';

  @override
  String get value_title_damaged => 'Damaged';

  @override
  String titleStatusDamagedWithParts(String count) {
    return 'damaged ($count parts)';
  }

  @override
  String get damageCrashPhotosSection => 'Damage / crash photos (optional)';

  @override
  String addDamagePhotosCount(Object count) {
    return 'Add damage photos ($count)';
  }

  @override
  String get damageImagesTitle => 'Damage images';

  @override
  String get viewDamagePhotosTooltip => 'View damage or crash photos';

  @override
  String get uploadingDamagePhotos => 'Uploading damage photos...';

  @override
  String get value_drive_fwd => 'FWD';

  @override
  String get value_drive_rwd => 'RWD';

  @override
  String get value_drive_awd => 'AWD';

  @override
  String get value_drive_4wd => '4WD';

  @override
  String get value_body_sedan => 'Sedan';

  @override
  String get value_body_suv => 'SUV';

  @override
  String get value_body_hatchback => 'Hatchback';

  @override
  String get value_body_coupe => 'Coupe';

  @override
  String get value_body_pickup => 'Pickup';

  @override
  String get value_body_van => 'Van';

  @override
  String get value_body_minivan => 'Minivan';

  @override
  String get value_body_motorcycle => 'Motorcycle';

  @override
  String get value_body_truck => 'Truck';

  @override
  String get value_body_cabriolet => 'Cabriolet';

  @override
  String get value_body_roadster => 'Roadster';

  @override
  String get value_body_micro => 'Micro';

  @override
  String get value_body_cuv => 'CUV';

  @override
  String get value_body_wagon => 'Wagon';

  @override
  String get value_body_minitruck => 'Minitruck';

  @override
  String get value_body_bigtruck => 'Bigtruck';

  @override
  String get value_body_supercar => 'Supercar';

  @override
  String get value_body_utv => 'UTV';

  @override
  String get value_body_atv => 'ATV';

  @override
  String get value_body_scooter => 'Scooter';

  @override
  String get value_body_super_bike => 'Super Bike';

  @override
  String get unit_km => 'km';

  @override
  String get unit_miles => 'mi';

  @override
  String get unit_liter_suffix => 'L';

  @override
  String get min => 'Min';

  @override
  String get max => 'Max';

  @override
  String get whatsappLabel => 'WhatsApp Number (with country code)';

  @override
  String get whatsappHint => '+9647XXXXXXXX';

  @override
  String get photosOptional => 'Photos (optional)';

  @override
  String get addPhotos => 'Add Photos';

  @override
  String get addMorePhotos => 'Add More Photos';

  @override
  String get addMoreListings => 'Add More Listings';

  @override
  String get defaultSort => 'Default';

  @override
  String get sort_price_low_high => 'Price (Low to High)';

  @override
  String get sort_price_high_low => 'Price (High to Low)';

  @override
  String get sort_year_newest => 'Year (Newest)';

  @override
  String get sort_year_oldest => 'Year (Oldest)';

  @override
  String get sort_mileage_low_high => 'Mileage (Low to High)';

  @override
  String get sort_mileage_high_low => 'Mileage (High to Low)';

  @override
  String get sort_newest => 'Newest';

  @override
  String get noCarsFound => 'No cars found';

  @override
  String get carNotFound => 'Car not found';

  @override
  String get chatOnWhatsApp => 'Chat on WhatsApp';

  @override
  String get chatOnCarzo => 'Chat on CarNet';

  @override
  String get chatCarzoOwnListing =>
      'You can\'t message yourself on your own listing.';

  @override
  String get unableToOpenWhatsApp => 'Unable to open WhatsApp';

  @override
  String get unableToMakeCall => 'Unable to make call';

  @override
  String get failedToShareListing => 'Failed to share listing';

  @override
  String get backToList => 'Back to list';

  @override
  String get quickSell => 'QUICK SELL';

  @override
  String get vehicleVideos => 'Vehicle Videos';

  @override
  String videoIndex(Object index) {
    return 'Video $index';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsEnablePush => 'Enable Push Notifications';

  @override
  String get settingsClearCaches => 'Clear Caches';

  @override
  String get settingsCachesSubtitle => 'Home, Details, Favorites, Similar';

  @override
  String get settingsCleared => 'Caches cleared';

  @override
  String get okAction => 'OK';

  @override
  String get sendOtp => 'Send OTP';

  @override
  String get passwordMin8 => 'Password must be at least 8 characters';

  @override
  String get otpSent => 'OTP sent';

  @override
  String get otpFailed => 'Failed to send OTP';

  @override
  String otpFailedWithMsg(Object msg) {
    return 'Failed to send OTP: $msg';
  }

  @override
  String devOtpCode(Object code) {
    return 'Dev OTP: $code';
  }

  @override
  String get english => 'English';

  @override
  String get arabic => 'Arabic';

  @override
  String get kurdish => 'Kurdish';

  @override
  String get mileageRangeLabel => 'Mileage Range';

  @override
  String get similarListings => 'Similar Listings';

  @override
  String listingUploadPartialFail(Object code) {
    return 'Listing created, but photo upload failed ($code).';
  }

  @override
  String failedToSubmitListing(Object msg) {
    return 'Failed to submit listing: $msg';
  }

  @override
  String get couldNotSubmitListing =>
      'Could not submit listing. Please try again.';

  @override
  String get listingVinAlreadyExists =>
      'This VIN is already used on another listing. Use a different VIN or edit your existing listing.';

  @override
  String get errorTitle => 'Error';

  @override
  String get createAccount => 'Create account';

  @override
  String get haveAccountLogin => 'Have an account? Login';

  @override
  String get notLoggedIn => 'You are not logged in';

  @override
  String get loginAction => 'Log In';

  @override
  String get loggedIn => 'Logged in';

  @override
  String get usernameLabel => 'Username';

  @override
  String get passwordLabel => 'Password';

  @override
  String get emailLabel => 'Email';

  @override
  String get phoneLabel => 'Phone';

  @override
  String get logout => 'Logout';

  @override
  String get devCodeTitle => 'Dev code';

  @override
  String useCodeToVerify(Object code) {
    return 'Use this code to verify: $code';
  }

  @override
  String get verificationCodeSent => 'Verification code sent';

  @override
  String get currencySymbol => '\$';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get selectDriveType => 'Select drive type';

  @override
  String get selectCylinderCount => 'Select cylinder count';

  @override
  String get selectSeating => 'Select seating';

  @override
  String get selectEngineSize => 'Select engine size';

  @override
  String get selectCity => 'Select city';

  @override
  String get enterWhatsAppNumber => 'Enter a WhatsApp number';

  @override
  String get useInternationalFormat =>
      'Use international format e.g. +9647XXXXXXX';

  @override
  String get anyOption => 'Any';

  @override
  String get city_baghdad => 'Baghdad';

  @override
  String get city_basra => 'Basra';

  @override
  String get city_erbil => 'Erbil';

  @override
  String get city_najaf => 'Najaf';

  @override
  String get city_karbala => 'Karbala';

  @override
  String get city_kirkuk => 'Kirkuk';

  @override
  String get city_mosul => 'Mosul';

  @override
  String get city_sulaymaniyah => 'Sulaymaniyah';

  @override
  String get city_dohuk => 'Dohuk';

  @override
  String get city_anbar => 'Anbar';

  @override
  String get city_halabja => 'Halabja';

  @override
  String get city_diyala => 'Diyala';

  @override
  String get city_maysan => 'Maysan';

  @override
  String get city_muthanna => 'Muthanna';

  @override
  String get city_qadisiyyah => 'Qadisiyyah';

  @override
  String get city_babil => 'Babil';

  @override
  String get city_dhi_qar => 'Dhi Qar';

  @override
  String get city_salaheldeen => 'Salaheldeen';

  @override
  String get city_wasit => 'Wasit';

  @override
  String get sellTitle => 'Sell';

  @override
  String get sellRequiresAuthTitle => 'Sign in to sell';

  @override
  String get sellRequiresAuthBody =>
      'Log in or create an account to list your car for sale.';

  @override
  String get createListingButton => 'Create listing';

  @override
  String get creatingListing => 'Creating listing...';

  @override
  String get uploadingPhotos => 'Uploading photos...';

  @override
  String get uploadingVideos => 'Uploading videos...';

  @override
  String addPhotosCount(Object count) {
    return 'Add photos ($count)';
  }

  @override
  String addVideoCount(Object count) {
    return 'Add video ($count)';
  }

  @override
  String get pleaseFixHighlightedFields => 'Please fix the highlighted fields';

  @override
  String get listingCreated => 'Listing created';

  @override
  String get listingTitle => 'Listing';

  @override
  String get shareAction => 'Share';

  @override
  String get callAction => 'Call';

  @override
  String get chatAction => 'Chat';

  @override
  String get favoriteAction => 'Favorite';

  @override
  String get favoritesAction => 'Favorites';

  @override
  String get editProfileAction => 'Edit profile';

  @override
  String get descriptionTitle => 'Description';

  @override
  String get retryAction => 'Retry';

  @override
  String get sellerPhoneNotAvailable => 'Seller phone not available';

  @override
  String get couldNotStartCall => 'Could not start a call';

  @override
  String get myListingsTitle => 'My listings';

  @override
  String get deleteListingTitle => 'Delete listing?';

  @override
  String get deleteListingBody => 'This will remove it from public listings.';

  @override
  String get listingRemovedSuccess => 'Listing removed';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteAction => 'Delete';

  @override
  String get editAction => 'Edit';

  @override
  String get comparisonEmptyHint => 'Add cars to comparison from listings.';

  @override
  String get comparisonSpecLabel => 'Spec';

  @override
  String get removeAction => 'Remove';

  @override
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsDark => 'Dark';

  @override
  String get enabledLabel => 'Enabled';

  @override
  String get disabledLabel => 'Disabled';

  @override
  String get accountLabel => 'Account';

  @override
  String get apiLabel => 'API';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get favoritesEmptyHint =>
      'Tap the heart on a listing to save it here.';

  @override
  String get browseCarsAction => 'Browse cars';

  @override
  String get chatEmptyHint =>
      'Message a seller from a listing to start a conversation.';

  @override
  String get originalMessageNotLoaded => 'Original message is not loaded.';

  @override
  String get messageCannotBeEmpty => 'Message cannot be empty.';

  @override
  String get chatUnavailableTitle => 'Chat unavailable';

  @override
  String get chatUnavailableBody =>
      'Messaging is temporarily disabled. Please try again later.';

  @override
  String get recentlyViewedEmptyHint => 'Open a car listing to add it here.';

  @override
  String get noCarsFoundHint => 'Try adjusting filters or browse all listings.';

  @override
  String get descriptionOptionalLabel => 'Description (optional)';

  @override
  String get plateBlurNote =>
      'Note: Plates are blurred only when you press Blur Plates.';

  @override
  String get invalidField => 'Invalid';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get engineTypeLabel => 'Engine type';

  @override
  String get locationLabel => 'Location';

  @override
  String get chooseAuthMethodTitle => 'Choose authentication method:';

  @override
  String get backAction => 'Back';

  @override
  String get verifyEmailTitle => 'Verify email';

  @override
  String get accountCreatedAndEmailVerified =>
      'Account created and email verified';

  @override
  String get emailVerifiedSuccessfully => 'Email verified successfully';

  @override
  String get verificationFailedMessage =>
      'Verification failed. Check the link or code and try again.';

  @override
  String get verifyEmailInstructions =>
      'Enter the verification code from the email we sent you, or open the verification link in this app.';

  @override
  String get verificationCodeLabel => 'Verification code';

  @override
  String get verificationCodeHint =>
      'Paste the code from the email or the link';

  @override
  String get pleaseEnterVerificationCode =>
      'Please enter the verification code';

  @override
  String get passwordResetSuccess => 'Password reset successfully';

  @override
  String get unableToResetPasswordCheckCode =>
      'Unable to reset password. Please check the code and try again.';

  @override
  String get unableToResetPasswordTryLater =>
      'Unable to reset password. Please try again later.';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get resetPasswordInstructions =>
      'Enter the code you received and choose a new password.';

  @override
  String get resetCodeLabel => 'Reset code';

  @override
  String get resetCodeHint => '6-digit or alphanumeric code';

  @override
  String get pleaseEnterResetCode => 'Please enter the reset code';

  @override
  String get newPasswordLabel => 'New password';

  @override
  String get pleaseEnterNewPassword => 'Please enter a new password';

  @override
  String get passwordUppercase =>
      'Password must contain at least one uppercase letter';

  @override
  String get passwordLowercase =>
      'Password must contain at least one lowercase letter';

  @override
  String get passwordNumber => 'Password must contain at least one number';

  @override
  String get passwordSpecialChar =>
      'Password must contain at least one special character';

  @override
  String get confirmNewPasswordLabel => 'Confirm new password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get switchToLightMode => 'Switch to Light Mode';

  @override
  String get switchToDarkMode => 'Switch to Dark Mode';

  @override
  String get carIdChatRoom => 'Car ID (chat room)';

  @override
  String get joinLabel => 'Join';

  @override
  String get unknownSender => 'Unknown';

  @override
  String get justNow => 'Just now';

  @override
  String get noMessagesYet => 'No messages yet.';

  @override
  String timeDaysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String timeHoursAgo(Object count) {
    return '$count hours ago';
  }

  @override
  String timeMinutesAgo(Object count) {
    return '$count minutes ago';
  }

  @override
  String get deleteAccountTitle => 'Delete account';

  @override
  String get deleteAccountBody =>
      'This will permanently delete your account and all your data (listings, messages, favorites). If full deletion is blocked by system constraints, your account is deactivated and personal data and listing media are scrubbed. This cannot be undone.';

  @override
  String get passwordRequiredConfirm => 'Password';

  @override
  String get passwordOptionalConfirm => 'Password';

  @override
  String get confirmWithPasswordHint =>
      'Enter your account password to confirm';

  @override
  String get deleteMyAccount => 'Delete my account';

  @override
  String get accountDeletedSnackbar => 'Your account has been deleted';

  @override
  String get apiBaseTitle => 'API base';

  @override
  String get apiBaseHint => 'https://carr-5hrm.onrender.com';

  @override
  String get resetButton => 'Reset';

  @override
  String get apiBaseUpdatedSnackbar =>
      'API base updated. Pull to refresh listings.';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get analyticsTitle => 'Analytics';

  @override
  String get failedToLoadListings => 'Failed to load your listings';

  @override
  String get noListingsFound => 'No Listings Found';

  @override
  String get createFirstListingForAnalytics =>
      'Create your first listing to see analytics';

  @override
  String get createListingButtonShort => 'Create Listing';

  @override
  String get analyticsOverview => 'Analytics Overview';

  @override
  String get listingsLabel => 'Listings';

  @override
  String get viewsLabel => 'Views';

  @override
  String get messagesLabel => 'Messages';

  @override
  String get callsLabel => 'Calls';

  @override
  String get sharesLabel => 'Shares';

  @override
  String get favoritesLabel => 'Favorites';

  @override
  String get analyticsDashboard => 'Analytics Dashboard';

  @override
  String get performanceInsights => 'Performance insights';

  @override
  String get performanceMetrics => 'Performance Metrics';

  @override
  String get engagementLabel => 'Engagement';

  @override
  String get engagementRate => 'Engagement Rate';

  @override
  String get fuelEconomyLabel => 'Fuel economy';

  @override
  String get comparisonTitle => 'Comparison';

  @override
  String get noCarsSelected => 'No cars selected';

  @override
  String get carLabel => 'Car';

  @override
  String get personalInformationTitle => 'Personal Information';

  @override
  String get firstNameLabel => 'First Name';

  @override
  String get lastNameLabel => 'Last Name';

  @override
  String get phoneNumberLabel => 'Phone Number';

  @override
  String get firstNameRequired => 'First name is required';

  @override
  String get lastNameRequired => 'Last name is required';

  @override
  String get usernameRequired => 'Username is required';

  @override
  String get usernameMin3 => 'Username must be at least 3 characters';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Please enter a valid email address';

  @override
  String get phoneRequired => 'Phone number is required';

  @override
  String get phoneInvalid => 'Please enter a valid phone number';

  @override
  String get profilePictureTitle => 'Profile Picture';

  @override
  String get tapCameraToChangeProfile =>
      'Tap the camera icon to change your profile picture';

  @override
  String get editProfileTitle => 'Edit Profile';

  @override
  String get saveChangesButton => 'Save Changes';

  @override
  String get savingLabel => 'Saving...';

  @override
  String get profileUpdatedSuccess => 'Profile updated successfully!';

  @override
  String get failedToLoadUserData => 'Failed to load user data';

  @override
  String get failedToUpdateProfile => 'Failed to update profile';

  @override
  String get verifyNewEmailDialogTitle => 'Verify your new email';

  @override
  String verifyNewEmailDialogMessage(Object email) {
    return 'We\'ll send a 6-digit code to $email to confirm you own it. Your other changes are saved already.';
  }

  @override
  String get emailUpdatedSuccess => 'Email updated successfully';

  @override
  String get failedToPickImage => 'Failed to pick image';

  @override
  String get emailOrPhoneLabel => 'Email or Phone Number';

  @override
  String get enterEmailOrPhoneHint =>
      'Enter your email address or phone number';

  @override
  String get forgotPasswordLink => 'Forgot password?';

  @override
  String get accountActionsTitle => 'Account Actions';

  @override
  String get helpSupportTitle => 'Help & Support';

  @override
  String get carComparisonCount => 'Car Comparison';

  @override
  String get addNewButton => 'Add New +';

  @override
  String yourListingsCount(Object count) {
    return 'Your Listings ($count)';
  }

  @override
  String get verifyEmailAction => 'Verify email';

  @override
  String get sendVerificationLinkToEmail =>
      'Send a verification link to your email';

  @override
  String get verifyPhoneAction => 'Verify phone';

  @override
  String get phoneVerificationRequiredMessage =>
      'Verify your phone number in Profile before posting listings or sending messages.';

  @override
  String get receiveCodeBySms => 'Receive a code by SMS';

  @override
  String get verificationEmailSent =>
      'Verification email sent. Check your inbox and spam.';

  @override
  String get codeSentEnterAbove => 'Code sent. Enter it above and tap Verify.';

  @override
  String get verifyButton => 'Verify';

  @override
  String get pleaseEnter6DigitCode => 'Please enter the 6-digit code';

  @override
  String get phoneVerifiedSuccess => 'Phone verified successfully';

  @override
  String get verifyPhoneDialogTitle => 'Verify phone';

  @override
  String verifyPhoneDialogMessage(Object phone) {
    return 'A 6-digit code will be sent to $phone.';
  }

  @override
  String get sixDigitCodeLabel => '6-digit code';

  @override
  String get sendCodeButton => 'Send code';

  @override
  String get noListingsYet => 'No Listings Yet';

  @override
  String get noListingsEmptyHint =>
      'You haven\'t created any car listings yet.\nStart by adding your first car!';

  @override
  String get addYourFirstCar => 'Add Your First Car';

  @override
  String get emailOrPhoneRequired => 'Email or phone number is required';

  @override
  String stepXOf5(Object step) {
    return 'Step $step of 6';
  }

  @override
  String get basicInformationTitle => 'Basic Information';

  @override
  String get basicInformationSubtitle =>
      'Tell us about your car\'s basic details';

  @override
  String get carDetailsTitle => 'Car Details';

  @override
  String get carDetailsSubtitle =>
      'Provide detailed information about your car';

  @override
  String get pricingContactTitle => 'Pricing & Contact';

  @override
  String get photosVideosTitle => 'Photos & Videos';

  @override
  String get reviewSubmitTitle => 'Review & Submit';

  @override
  String get selectBrandFirst => 'Select brand first';

  @override
  String get nextStep => 'Next Step';

  @override
  String get previousButton => 'Previous';

  @override
  String get tapToSelect => 'Tap to select';

  @override
  String get pleaseFillRequired => 'Please complete';

  @override
  String get pleaseSelectBrand => 'Please select a brand';

  @override
  String get pleaseSelectModel => 'Please select a model';

  @override
  String get pleaseSelectTrim => 'Please select a trim';

  @override
  String get pleaseSelectYear => 'Please select a year';

  @override
  String get pleaseEnterYear => 'Please enter year';

  @override
  String get enterYearHint => 'Enter year (e.g. 2024)';

  @override
  String get yearInvalid => 'Invalid year';

  @override
  String get yearOutOfRange => 'Year out of range';

  @override
  String get confirmYear => 'Confirm year';

  @override
  String get typeManually => 'Type manually';

  @override
  String get mileageKmLabel => 'Mileage (km)';

  @override
  String get enterMileage => 'Enter mileage';

  @override
  String get pleaseEnterMileage => 'Please enter mileage';

  @override
  String get invalidMileage => 'Invalid mileage';

  @override
  String get mileageNegative => 'Mileage cannot be negative';

  @override
  String get pleaseSelectMileage => 'Please select mileage';

  @override
  String get confirmMileage => 'Confirm mileage';

  @override
  String get pleaseSelectCondition => 'Please select condition';

  @override
  String get pleaseSelectTransmission => 'Please select transmission';

  @override
  String get pleaseSelectFuelType => 'Please select fuel type';

  @override
  String get pleaseSelectBodyType => 'Please select body type';

  @override
  String get pleaseSelectColor => 'Please select color';

  @override
  String get pleaseSelectDriveType => 'Please select drive type';

  @override
  String get pleaseSelectRegionSpecs => 'Please select region specs';

  @override
  String get pleaseSelectSeating => 'Please select seating';

  @override
  String get pleaseSelectEngineSize => 'Please select engine size';

  @override
  String get pleaseSelectCylinderCount => 'Please select cylinder count';

  @override
  String get contactForPrice => 'Contact for price';

  @override
  String get comparisonCleared => 'Comparison cleared';

  @override
  String get clearComparisonTitle => 'Clear comparison?';

  @override
  String get clearComparisonBody =>
      'This removes all cars from your comparison list.';

  @override
  String get photosRequired => 'Photos (Required)';

  @override
  String get videosOptional => 'Videos (Optional)';

  @override
  String get status => 'Status';

  @override
  String get sellButton => 'Sell';

  @override
  String get value_transmission_semi_automatic => 'Semi-automatic';

  @override
  String get value_transmission_cvt => 'CVT';

  @override
  String get value_condition_certified => 'Certified';

  @override
  String get value_trim_base => 'Base';

  @override
  String get value_trim_sport => 'Sport';

  @override
  String get value_trim_luxury => 'Luxury';

  @override
  String get value_color_black => 'Black';

  @override
  String get value_color_white => 'White';

  @override
  String get value_color_silver => 'Silver';

  @override
  String get value_color_gray => 'Gray';

  @override
  String get value_color_red => 'Red';

  @override
  String get value_color_blue => 'Blue';

  @override
  String get value_color_green => 'Green';

  @override
  String get value_color_yellow => 'Yellow';

  @override
  String get value_color_orange => 'Orange';

  @override
  String get value_color_purple => 'Purple';

  @override
  String get value_color_brown => 'Brown';

  @override
  String get value_color_beige => 'Beige';

  @override
  String get value_color_gold => 'Gold';

  @override
  String get savedSearchesTitle => 'Saved Searches';

  @override
  String get noSavedSearchesYet => 'No saved searches yet';

  @override
  String get savedSearchesHint =>
      'Save a search from the Search page to get alerts for new matches';

  @override
  String get compareLabel => 'compare +';

  @override
  String get addedLabel => 'Added';

  @override
  String get clearAll => 'Clear all';

  @override
  String comparisonMaxLimit(Object max) {
    return 'Maximum $max cars can be compared';
  }

  @override
  String get removedFromComparison => 'Removed from comparison';

  @override
  String addedToComparison(Object count, Object max) {
    return 'Added to comparison ($count/$max)';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String daysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String get noFiltersApplied => 'No filters applied';

  @override
  String get unnamedSearch => 'Unnamed Search';

  @override
  String get applySearch => 'Apply Search';

  @override
  String get renameTooltip => 'Rename';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get verifiedDealerLabel => 'Verified dealer';

  @override
  String get dealerApplicationPendingLabel => 'Dealer application pending';

  @override
  String get dealerApplicationDeclinedLabel => 'Dealer application declined';

  @override
  String get personalAccountLabel => 'Personal account';

  @override
  String get dealershipLabel => 'Dealership';

  @override
  String get dealerFallbackLabel => 'Dealer';

  @override
  String get openInGoogleMapsAction => 'Open in Google Maps';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to logout?';

  @override
  String get accountInformationTitle => 'Account Information';

  @override
  String get termsOfServiceTitle => 'Terms of Service';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get helpHowCanWeHelp => 'How can we help?';

  @override
  String get helpBuyingSection => 'Buying';

  @override
  String get helpSellingSection => 'Selling';

  @override
  String get helpDealersSection => 'Dealers';

  @override
  String get helpPaymentsSection => 'Payments';

  @override
  String get helpContactSupport => 'Contact support';

  @override
  String get helpFaqContactSellerQuestion => 'How do I contact a seller?';

  @override
  String get helpFaqContactSellerAnswer =>
      'Open a listing and use Call, WhatsApp, or Chat on the detail page.';

  @override
  String get helpFaqListingsVerifiedQuestion => 'Are listings verified?';

  @override
  String get helpFaqListingsVerifiedAnswer =>
      'Dealers with an approved badge are reviewed by our team. Always inspect a vehicle in person before paying.';

  @override
  String get helpFaqPostListingQuestion => 'How do I post a listing?';

  @override
  String get helpFaqPostListingAnswer =>
      'Sign in, tap Sell, and follow the steps to add photos, price, and details.';

  @override
  String get helpFaqEditDeleteListingQuestion =>
      'How do I edit or delete my listing?';

  @override
  String get helpFaqEditDeleteListingAnswer =>
      'Open your listing from My Listings or the listing page (owner tools) to edit or delete.';

  @override
  String get helpFaqRegisterDealerQuestion => 'How do I register as a dealer?';

  @override
  String get helpFaqRegisterDealerAnswer =>
      'Choose dealer signup and submit your dealership details. Approval may take 1–2 business days.';

  @override
  String get helpFaqPaymentsQuestion => 'Does the app handle payments?';

  @override
  String get helpFaqPaymentsAnswer =>
      'Payments are arranged directly between buyer and seller. Never send money before seeing the vehicle.';

  @override
  String get helpCouldNotOpenLink => 'Could not open link';

  @override
  String get whatsappAction => 'WhatsApp';

  @override
  String get chatSendPhotosVideosTitle => 'Send photos/videos';

  @override
  String get chatSendPhotosVideosSubtitle =>
      'Select multiple images and videos';

  @override
  String get chatSendImageTitle => 'Send image';

  @override
  String get chatSendImageSubtitle => 'Select multiple images';

  @override
  String get chatSendVideoTitle => 'Send video';

  @override
  String get chatSendVideoSubtitle => 'Select multiple videos';

  @override
  String get listingSubmittedPending =>
      'Your listing is under review and hidden from buyers for now. Track it in My Listings → Pending.';

  @override
  String get listingSubmittedSuccess =>
      'Your listing is live. Find it in My Listings → Active.';

  @override
  String get listingPendingBadge => 'Under review';

  @override
  String get homeOfflineCachedBanner =>
      'You are offline. Showing cached listings.';

  @override
  String get offlineBannerMessage =>
      'You\'re offline. Some features may not work.';

  @override
  String get myListingsPendingFilter => 'Pending';

  @override
  String get myListingsPendingExplainer =>
      'These listings are not visible to buyers yet. We review new posts for quality and safety — most are approved quickly.';

  @override
  String get myListingsNoPendingTitle => 'No pending listings';

  @override
  String get myListingsNoPendingHint =>
      'Listings waiting for review will appear here.';

  @override
  String get joinAnd => ' and ';

  @override
  String get labelPlateType => 'Plate type';

  @override
  String get labelPlateCity => 'Plate city';

  @override
  String get plateTypePrivate => 'Private';

  @override
  String get plateTypeCommercial => 'Commercial';

  @override
  String get plateTypeTaxi => 'Taxi';

  @override
  String get plateTypeGovernment => 'Government';

  @override
  String get plateTypeTemporary => 'Temporary';

  @override
  String get plateTypeDiplomatic => 'Diplomatic';

  @override
  String get plateTypePolice => 'Police';

  @override
  String get regionSpecGcc => 'GCC';

  @override
  String get regionSpecUs => 'US';

  @override
  String get regionSpecIraq => 'Iraq';

  @override
  String get regionSpecCanada => 'Canada';

  @override
  String get regionSpecEu => 'EU';

  @override
  String get regionSpecCn => 'CN';

  @override
  String get regionSpecKorea => 'Korea';

  @override
  String get regionSpecRu => 'RU';

  @override
  String get regionSpecIran => 'Iran';

  @override
  String get vinCopied => 'VIN copied';

  @override
  String get sellStep1Photos => 'Step 1: Photos';

  @override
  String get sellStep2BasicInfo => 'Step 2: Basic info';

  @override
  String get sellStep3Details => 'Step 3: Details';

  @override
  String get sellStep4Pricing => 'Step 4: Pricing';

  @override
  String get sellStep5Plates => 'Step 5: Plates';

  @override
  String get sellStep6Review => 'Step 6: Review';

  @override
  String get seats => 'seats';

  @override
  String get labelCylinders => 'cylinders';

  @override
  String get labelDealership => 'Dealership';

  @override
  String get labelPhone => 'Phone';

  @override
  String get labelLocation => 'Location';

  @override
  String get pleaseSelectAtLeastOnePhoto => 'Please select at least one photo';

  @override
  String get couldNotLoadListings => 'Could not load listings';

  @override
  String get homeFeedLoadingListings => 'Loading listings...';

  @override
  String get homeFeedSortingListings => 'Sorting listings...';

  @override
  String get homeFeedCachedResultsBanner => 'Showing cached results';

  @override
  String get homeFeedSortedLocally => 'Sorted locally (server unavailable)';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get homeFeedSortDisabled =>
      'Sorting temporarily disabled due to server issue';

  @override
  String get homeFeedNetworkError =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String homeFeedServerError(String statusCode) {
    return 'Server error ($statusCode). Please try again later.';
  }

  @override
  String get acceptTermsRequired =>
      'Please accept the Terms and Privacy Policy';

  @override
  String get videoPlaybackFailed => 'Could not play this video.';

  @override
  String get photosUploaded => 'Photos uploaded';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get missingDealerId => 'Missing dealer id';

  @override
  String get markAsAvailable => 'Mark as available';

  @override
  String get markAsSold => 'Mark as sold';

  @override
  String get reportListing => 'Report listing';

  @override
  String get reportSeller => 'Report seller';

  @override
  String get unableToSelectThatPhoto => 'Unable to select that photo.';

  @override
  String get pleaseUploadAClearPhotoOfYourBusiness =>
      'Please upload a clear photo of your business.';

  @override
  String get dealershipDetailsSubmittedYourApplicationIsPendingReview =>
      'Dealership details submitted. Your application is pending review.';

  @override
  String get addAPhotoThatHelpsUsVerifyThisDealership =>
      'Add a photo that helps us verify this dealership';

  @override
  String get privateDealershipPhotoUploaded =>
      'Private dealership photo uploaded';

  @override
  String get createDealershipAccount => 'Create dealership account';

  @override
  String get finalSetupStep => 'Final setup step';

  @override
  String get buildYourDealershipPresence => 'Build your dealership presence';

  @override
  String
  get addAccurateBusinessDetailsSoBuyersCanTrustAndContactYourDealership =>
      'Add accurate business details so buyers can trust and contact your dealership.';

  @override
  String get reviewUsuallyTakes12BusinessDays =>
      'Review usually takes 1–2 business days';

  @override
  String get changesRequested => 'Changes requested';

  @override
  String get businessInformation => 'Business information';

  @override
  String get theseDetailsWillAppearOnYourPublicDealershipProfile =>
      'These details will appear on your public dealership profile.';

  @override
  String get dealershipName => 'Dealership name';

  @override
  String get yourRegisteredOrTradingName => 'Your registered or trading name';

  @override
  String get businessPhone => 'Business phone';

  @override
  String get aNumberBuyersCanReach => 'A number buyers can reach';

  @override
  String get dealershipLocation => 'Dealership location';

  @override
  String get cityDistrictAndStreet => 'City, district, and street';

  @override
  String get aboutYourDealershipOptional => 'About your dealership (optional)';

  @override
  String get describeYourInventoryExperienceAndCustomerService =>
      'Describe your inventory, experience, and customer service';

  @override
  String get dealershipVerificationPhoto => 'Dealership verification photo';

  @override
  String
  get requiredUsedPrivatelyByOurReviewTeamAndNeverShownOnYourPublicProfile =>
      'Required · Used privately by our review team and never shown on your public profile.';

  @override
  String get chooseVerificationPhoto => 'Choose verification photo';

  @override
  String get replacePhoto => 'Replace photo';

  @override
  String
  get uploadOneClearRecentPhotoOfTheDealershipStorefrontCarsForSaleShowroomOrO =>
      'Upload one clear, recent photo of the dealership storefront, cars for sale, showroom, or office—anything that helps our team confirm the business is genuine.';

  @override
  String get submitting => 'Submitting…';

  @override
  String get submitForReview => 'Submit for review';

  @override
  String get yourBusinessInformationIsHandledSecurely =>
      'Your business information is handled securely.';

  @override
  String get forgotPassword => 'Forgot Password';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get checkYourEmail => 'Check Your Email';

  @override
  String get checkYourMessages => 'Check your messages';

  @override
  String get enterTheEmailAddressForYourAccountWeWillSendAResetCode =>
      'Enter the email address for your account. We will send a reset code.';

  @override
  String get enterThePhoneNumberForYourAccountWeWillSendAResetCodeBySMS =>
      'Enter the phone number for your account. We will send a reset code by SMS.';

  @override
  String
  weVeSentAPasswordResetLinkToEmailPleaseCheckYourEmailAndFollowTheInstruc(
    String email,
  ) {
    return 'We\'ve sent a password reset link to $email. Please check your email and follow the instructions.';
  }

  @override
  String ifAnAccountExistsForPhoneWeSentAPasswordResetCodeBySMS(String phone) {
    return 'If an account exists for $phone, we sent a password reset code by SMS.';
  }

  @override
  String
  get ifYouDonTSeeItCheckYourSpamOrJunkFolderTheLinkIsOnlySentIfAnAccountExist =>
      'If you don\'t see it, check your spam or junk folder. The link is only sent if an account exists for this email.';

  @override
  String
  get smsMayTakeAMinuteOrTwoACodeIsOnlySentIfAnAccountExistsForThisNumber =>
      'SMS may take a minute or two. A code is only sent if an account exists for this number.';

  @override
  String get pleaseEnterAValidEmail => 'Please enter a valid email';

  @override
  String get pleaseEnterAValidPhoneNumberAtLeast8Digits =>
      'Please enter a valid phone number (at least 8 digits)';

  @override
  String get sendResetLink => 'Send Reset Link';

  @override
  String get sendResetCodeSMS => 'Send reset code (SMS)';

  @override
  String get iHaveTheCodeSetNewPassword => 'I have the code – set new password';

  @override
  String get backToLogin => 'Back to Login';

  @override
  String get commonBack => 'Back';

  @override
  String get tooManyResetAttemptsPleaseWaitALittleAndTryAgain =>
      'Too many reset attempts. Please wait a little and try again.';

  @override
  String get failedToSendResetLinkCheckYourEmailAndTryAgainLater =>
      'Failed to send reset link. Check your email and try again later.';

  @override
  String get failedToSendSMSCheckTheNumberAndTryAgainLater =>
      'Failed to send SMS. Check the number and try again later.';

  @override
  String
  get thisPhoneNumberIsRegisteredToAPersonalAccountPleaseUsePersonalLoginInste =>
      'This phone number is registered to a personal account. Please use personal login instead.';

  @override
  String
  get thisPhoneNumberIsRegisteredToADealerAccountPleaseUseDealerLoginInstead =>
      'This phone number is registered to a dealer account. Please use dealer login instead.';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get onboardingBrowseTitle => 'Browse listings';

  @override
  String get onboardingBrowseBody =>
      'Search and filter cars near you. Open any listing for photos, specs, and seller chat.';

  @override
  String get onboardingFavoritesTitle => 'Save favorites';

  @override
  String get onboardingFavoritesBody =>
      'Tap the heart on a listing — find everything again from Home or Profile.';

  @override
  String get onboardingSellTitle => 'Sell your car';

  @override
  String get onboardingSellBody =>
      'Use Sell in the bottom bar to list a car in a few guided steps.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get enterYourPhoneNumberToLogInOrCreateAnAccount =>
      'Enter your phone number to log in or create an account.';

  @override
  String get accountType => 'Account type';

  @override
  String get dealerApplicationNeedsChanges =>
      'Dealer application needs changes';

  @override
  String get recentlyViewed => 'Recently viewed';

  @override
  String get editDealerPage => 'Edit dealer page';

  @override
  String get guest => 'Guest';

  @override
  String get signInToAccessYourProfileFeatures =>
      'Sign in to access your profile features.';

  @override
  String get iAgreeToThe => 'I agree to the ';

  @override
  String get terms => 'Terms';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get searchAppliedSuccessfully => 'Search applied successfully!';

  @override
  String get appliedFilters => 'Applied Filters:';

  @override
  String get close => 'Close';

  @override
  String get alerts => 'Alerts';

  @override
  String get owners => 'Owners';

  @override
  String get accidentHistory => 'Accident History';

  @override
  String get deleteSavedSearch => 'Delete saved search?';

  @override
  String get thisWillPermanentlyRemoveThisSavedSearchThisCannotBeUndone =>
      'This will permanently remove this saved search. This cannot be undone.';

  @override
  String get featured => 'FEATURED';

  @override
  String get less => 'Less';

  @override
  String get more => 'More';

  @override
  String get selectFromList => 'Select from list';

  @override
  String get searchMakeOrModel => 'Search make or model';

  @override
  String get noMakesOrModelsMatchYourSearch =>
      'No makes or models match your search.';

  @override
  String get make => 'Make';

  @override
  String get sendMessage => 'Send message';

  @override
  String filterSelectedCount(String count) {
    return '$count selected';
  }

  @override
  String get apply => 'Apply';

  @override
  String get youLlBeNotifiedWhenAMatchingCarIsListed =>
      'You\'ll be notified when a matching car is listed';

  @override
  String get view => 'View';

  @override
  String get logIn => 'Log in';

  @override
  String get searchBrandsModels => 'Search brands & models';

  @override
  String get showCars => 'Show Cars';

  @override
  String get searchCars => 'Search Cars';

  @override
  String get saveSearch => 'Save search';

  @override
  String get notifyMe => 'Notify me';

  @override
  String get featuredListings => 'Featured Listings';

  @override
  String get plate => 'Plate';

  @override
  String get viewDescription => 'View description';

  @override
  String get licensePlates => 'License plates';

  @override
  String get draftInProgress => 'Draft in progress';

  @override
  String get discardDraft => 'Discard draft?';

  @override
  String get thisWillPermanentlyDeleteThisDraftListingThisCannotBeUndone =>
      'This will permanently delete this draft listing. This cannot be undone.';

  @override
  String get discard => 'Discard';

  @override
  String get failedToBlurPlatesPleaseTryAgain =>
      'Failed to blur plates. Please try again.';

  @override
  String get platesBlurredSuccessfully => 'Plates blurred successfully.';

  @override
  String get inProgress => 'In progress';

  @override
  String get draftsInProgress => 'Drafts in progress';

  @override
  String
  get continueAnyDraftDiscardOneOrStartANewListingWhileKeepingTheOthers =>
      'Continue any draft, discard one, or start a new listing while keeping the others.';

  @override
  String get startNewListing => 'Start new listing';

  @override
  String get startANewListing => 'Start a new listing';

  @override
  String get noDraftsYetCreateYourFirstCarListingToGetStarted =>
      'No drafts yet. Create your first car listing to get started.';

  @override
  String get specsAppliedYearSetStep2FieldsPreFilled =>
      'Specs applied — year set; step 2 fields pre-filled.';

  @override
  String get search => 'Search...';

  @override
  String get loadingVehicleSpecs => 'Loading vehicle specs…';

  @override
  String get specDatabaseUnavailableRestartTheAppAfterFlutterPubGet =>
      'Spec database unavailable. Restart the app after flutter pub get.';

  @override
  String get catalogAutoFill => 'Catalog auto-fill';

  @override
  String get selectAModelYearToLoadMatchingSpecs =>
      'Select a model year to load matching specs.';

  @override
  String get modelYear => 'Model year';

  @override
  String get youCanChangeTheseInStep2 => 'You can change these in step 2.';

  @override
  String get specsAvailableForThisYear => 'Specs available for this year.';

  @override
  String get applySpecs => 'Apply specs';

  @override
  String get specifications => 'Specifications';

  @override
  String get vinOptional => 'VIN (optional)';

  @override
  String get vinMustBe17Characters => 'VIN must be 17 characters';

  @override
  String get setYourPriceAndContactInformation =>
      'Set your price and contact information';

  @override
  String get whatsappPhoneNumber => 'WhatsApp/Phone Number';

  @override
  String get whatsappPhoneNumber2 => 'WhatsApp/Phone Number *';

  @override
  String get listingContactPhonesTitle => 'Contact phone numbers';

  @override
  String get listingContactPhonesHint =>
      'Add up to 3 numbers. Verify each with a code.';

  @override
  String get addPhoneNumber => 'Add phone number';

  @override
  String listingContactPhoneN(int n) {
    return 'Phone $n';
  }

  @override
  String get phoneVerifiedBadge => 'Verified';

  @override
  String get verifyContactPhonesBeforeContinuing =>
      'Verify each contact phone with a code before continuing.';

  @override
  String get duplicateContactPhoneError =>
      'This phone number is already added.';

  @override
  String get pleaseEnterPhoneNumber => 'Please enter phone number';

  @override
  String get pleaseEnterAValidPhoneNumber =>
      'Please enter a valid phone number';

  @override
  String get addDetailsAboutTheCarConditionFeaturesOrNotes =>
      'Add details about the car, condition, features, or notes';

  @override
  String priceSelectedCurrencyOptional(String selectedCurrency) {
    return 'Price ($selectedCurrency) (optional)';
  }

  @override
  String get enterPrice => 'Enter price';

  @override
  String get invalidPrice => 'Invalid price';

  @override
  String get priceCannotBeNegative => 'Price cannot be negative';

  @override
  String get damageCrashPhotos => 'Damage / crash photos';

  @override
  String get photos => 'Photos';

  @override
  String get tapTheStarOnAPhotoToSetItAsTheCoverImageShownFirstInYourListing =>
      'Tap the star on a photo to set it as the cover image shown first in your listing.';

  @override
  String get cover => 'Cover';

  @override
  String get blurringLicensePlatesInTheBackground =>
      'Blurring license plates in the background…';

  @override
  String get plateBlurReadyYouCanChooseLater =>
      'Plate blur ready — you can choose later';

  @override
  String get videos => 'Videos';

  @override
  String get addMoreVideos => 'Add More Videos';

  @override
  String get addVideos => 'Add Videos';

  @override
  String get stillBlurringPlatesInTheBackgroundPhotosWillAppearHereWhenReady =>
      'Still blurring plates in the background. Photos will appear here when ready.';

  @override
  String get blurredPhotos => 'Blurred photos';

  @override
  String get blurredDamagePhotos => 'Blurred damage photos';

  @override
  String get noPhotosAvailable => 'No photos available.';

  @override
  String get blurredPhotosAreNotReadyYet => 'Blurred photos are not ready yet.';

  @override
  String get blurPlatesNow => 'Blur plates now';

  @override
  String get originalPhotos => 'Original photos';

  @override
  String get originalDamagePhotos => 'Original damage photos';

  @override
  String get chooseWhetherToPublishPhotosWithBlurredPlates =>
      'Choose whether to publish photos with blurred plates';

  @override
  String get blurPlates => 'Blur plates?';

  @override
  String get yesBlurPlates => 'Yes, blur plates';

  @override
  String get noKeepOriginal => 'No, keep original';

  @override
  String get yesUseBlurredPhotos => 'Yes, use blurred photos';

  @override
  String get hideLicensePlatesOnYourListing =>
      'Hide license plates on your listing';

  @override
  String get noKeepOriginalPhotos => 'No, keep original photos';

  @override
  String get publishThePhotosExactlyAsYouUploadedThem =>
      'Publish the photos exactly as you uploaded them';

  @override
  String get pleaseChooseWhetherToBlurPlates =>
      'Please choose whether to blur plates';

  @override
  String get pleaseWaitForPlateBlurringToFinish =>
      'Please wait for plate blurring to finish';

  @override
  String get blurPlatesFirstOrChooseToKeepOriginals =>
      'Blur plates first, or choose to keep originals';

  @override
  String get callSeller => 'Call Seller';

  @override
  String get privateSeller => 'Private seller';

  @override
  String get dealer => 'Dealer';

  @override
  String get verified => 'Verified';

  @override
  String get email => 'Email';

  @override
  String get tapToOpenDealershipPage => 'Tap to open dealership page';

  @override
  String get cannotAddToComparison => 'Cannot add to comparison';

  @override
  String get dealershipLogo => 'Dealership logo';

  @override
  String get coverImage => 'Cover image';

  @override
  String get openingHours => 'Opening hours';

  @override
  String get youCanAlsoReviewYourContactDetailsLocationDescriptionAndMapPin =>
      'You can also review your contact details, location, description, and map pin.';

  @override
  String get gotIt => 'Got it';

  @override
  String get later => 'Later';

  @override
  String get completeProfile => 'Complete profile';

  @override
  String get searchByBrand => 'Search by Brand';

  @override
  String get searchByModel => 'Search by Model';

  @override
  String get searchBrands => 'Search brands...';

  @override
  String get searchModels => 'Search models...';

  @override
  String get listingMarkedAsSold => 'Listing marked as sold';

  @override
  String get listingIsAvailableAgain => 'Listing is available again';

  @override
  String get setUpYourDealerPage => 'Set up your dealer page';

  @override
  String get yourDealershipIsApproved => 'Your dealership is approved!';

  @override
  String
  get yourDealershipIsApprovedFillInTheInformationOnThisPageToFinishSettingUpT =>
      'Your dealership is approved. Fill in the information on this page to finish setting up the dealer page buyers will see.';

  @override
  String
  get completeYourPublicDealerPageSoBuyersCanRecognizeYourBusinessAndKnowWhenT =>
      'Complete your public dealer page so buyers can recognize your business and know when to contact you.';

  @override
  String get switchToUSD => 'Switch to USD';

  @override
  String get switchToIQD => 'Switch to IQD';

  @override
  String get continueAction => 'Continue';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get changeProfilePhoto => 'Change profile photo';

  @override
  String get playVideo => 'Play video';

  @override
  String get pauseVideo => 'Pause video';
}
