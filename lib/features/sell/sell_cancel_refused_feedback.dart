import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Test hook / stable finder for the "too late to cancel" SnackBar text.
const Key kSellCancelTooLateKey = ValueKey<String>('sell-cancel-too-late');

/// User feedback for a REFUSED cancel (`PendingSellSubmissionService
/// .cancelSubmission` returned null because the worker already confirmed every
/// upload and is only publishing the listing): without this the tap on
/// "Cancel upload" appeared to do nothing.
///
/// The message is a polite live region (SnackBars are also announced by the
/// platform), so screen readers speak it without moving focus.
void showSellCancelTooLateFeedback(
  ScaffoldMessengerState? messenger,
  AppLocalizations loc,
) {
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Semantics(
        liveRegion: true,
        container: true,
        child: Text(loc.a11yUploadCancelTooLate, key: kSellCancelTooLateKey),
      ),
    ),
  );
}
