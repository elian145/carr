import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Localized UI helpers formerly backed by inline ar/ku maps.
/// Prefer [AppLocalizations] getters directly at call sites when practical.
String yesText(BuildContext context) => AppLocalizations.of(context)!.commonYes;

String noText(BuildContext context) => AppLocalizations.of(context)!.commonNo;

String pleaseSelectPhotoText(BuildContext context) =>
    AppLocalizations.of(context)!.pleaseSelectAtLeastOnePhoto;

String listingSubmittedSuccessText(BuildContext context) =>
    AppLocalizations.of(context)!.listingSubmittedSuccess;

String listingSubmittedPendingText(BuildContext context) =>
    AppLocalizations.of(context)!.listingSubmittedPending;

String couldNotLoadListingsText(BuildContext context) =>
    AppLocalizations.of(context)!.couldNotLoadListings;

String homeFeedLoadingListingsText(BuildContext context) =>
    AppLocalizations.of(context)!.homeFeedLoadingListings;

String homeFeedSortingListingsText(BuildContext context) =>
    AppLocalizations.of(context)!.homeFeedSortingListings;

String homeFeedSortedLocallyText(BuildContext context) =>
    AppLocalizations.of(context)!.homeFeedSortedLocally;

String homeFeedSortDisabledText(BuildContext context) =>
    AppLocalizations.of(context)!.homeFeedSortDisabled;

String homeFeedNetworkErrorText(BuildContext context) =>
    AppLocalizations.of(context)!.homeFeedNetworkError;

String homeFeedServerErrorText(BuildContext context, String statusCode) =>
    AppLocalizations.of(context)!.homeFeedServerError(statusCode);

String acceptTermsRequiredText(BuildContext context) =>
    AppLocalizations.of(context)!.acceptTermsRequired;

String videoPlaybackFailedText(BuildContext context) =>
    AppLocalizations.of(context)!.videoPlaybackFailed;

String photosUploadedText(BuildContext context) =>
    AppLocalizations.of(context)!.photosUploaded;
