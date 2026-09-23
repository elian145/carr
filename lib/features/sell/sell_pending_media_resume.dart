import '../../shared/debug/app_log.dart';
import 'pending_sell_submission_service.dart';

/// Thin, backward-compatible entry point kept for existing call sites
/// (`bootstrap.dart`, `MyListingsPage._loadDrafts`, and this feature's own
/// retryable-error fallback in `sell_step5_logic.dart`).
///
/// The actual work — discovering pending submissions, migrating any older
/// pending-media record, and resuming them without duplicating the listing
/// or its media — now lives in [PendingSellSubmissionService], which also
/// covers submissions interrupted *before* the listing was created (this
/// class historically only handled "listing created, media still
/// pending"). See that class for the full state machine.
class SellPendingMediaResume {
  SellPendingMediaResume._();

  /// Returns true when at least one durably-recorded submission was
  /// resumed by this call (and has finished, one way or another, by the
  /// time this returns — see [PendingSellSubmissionService.resumeAll]).
  static Future<bool> tryResume() async {
    try {
      return await PendingSellSubmissionService.instance.resumeAll();
    } catch (e, st) {
      logNonFatal(e, st, 'SellPendingMediaResume');
      return false;
    }
  }
}
