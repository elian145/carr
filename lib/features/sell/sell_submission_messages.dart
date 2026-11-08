import '../../l10n/app_localizations.dart';

/// Machine-origin submission messages that are persisted in the durable
/// submission record (`lastErrorMessage`) in English and later shown to the
/// seller in My Listings. They are mapped to the app locale at display time
/// by [localizedSellSubmissionDetail] (F-22) -- the stored value stays stable.
const String kSellMsgAuthRequired = 'Authentication required';
const String kSellMsgPhotoProcessingFailed =
    'Photo processing failed. Please try again.';
const String kSellMsgCancelledByUser = 'Cancelled by the user';

/// Localizes a stored submission error [detail] when it is one of the known
/// client-originated messages; server-provided text is returned unchanged.
String localizedSellSubmissionDetail(AppLocalizations? loc, String detail) {
  if (loc == null) return detail;
  switch (detail.trim()) {
    case kSellMsgAuthRequired:
      return loc.loginRequired;
    case kSellMsgPhotoProcessingFailed:
      return loc.sellPhotoProcessingFailed;
    case kSellMsgCancelledByUser:
      return loc.sellSubmissionCancelledByUser;
  }
  return detail;
}
