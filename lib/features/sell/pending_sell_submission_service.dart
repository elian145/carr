import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/car_service.dart';
import '../../services/connectivity_service.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/debug/expected_client_noise.dart';
import '../../shared/listings/listing_identity.dart' as listing_identity;
import '../../shared/listings/listing_image_media.dart';
import '../../shared/listings/listing_status.dart';
import '../../shared/prefs/sell_draft_media_persistence.dart';
import '../../shared/prefs/sell_pending_media_prefs.dart';
import '../../shared/prefs/sell_submission_state_prefs.dart';
import '../../shared/ui/app_haptics.dart';
import 'sell_draft_helpers.dart';
import 'sell_listing_media_upload.dart';
import 'sell_listing_payload.dart';
import 'sell_listing_submit_result.dart';
import 'sell_photo_prestage.dart';
import 'sell_server_transcode_video.dart';
import 'sell_video_helpers.dart';

/// Coarse phase reported while a submission runs, for UI display only.
/// Correctness (no duplicate listing / no duplicate media) never depends on
/// this — it is derived purely for progress messaging.
enum SellSubmissionPhase {
  creating,
  uploadingPhotos,
  uploadingVideos,
  uploadingDamagePhotos,
  done,

  /// Phase 3B: finer-grained sub-phases of [uploadingVideos] specific to
  /// the server-transcode fallback pipeline (see
  /// `SellListingMediaUpload.SellMediaUploadPhase`'s matching
  /// `serverTranscodeUploading`/`serverTranscodeProcessing`/
  /// `serverTranscodeFinishing` values, mapped 1:1 in the `onPhase`
  /// switch below). UI-only, exactly like every other value in this
  /// enum -- never affects correctness/resume/idempotency.
  uploadingVideoSource,
  processingVideoOnServer,
  finishingVideoUpload,
}

/// Live progress snapshot for the global "Uploading listing…" banner.
class SellSubmissionUiStatus {
  const SellSubmissionUiStatus({
    required this.draftId,
    required this.phase,
    required this.completedMediaCount,
    required this.totalMediaCount,
  });

  final String draftId;
  final SellSubmissionPhase phase;
  final int completedMediaCount;
  final int totalMediaCount;
}

/// One-shot terminal outcome of a submission run, for a global
/// success/needs-attention notification independent of whichever page (if
/// any) happens to be visible when it fires.
class SellSubmissionEvent {
  const SellSubmissionEvent({
    required this.draftId,
    required this.success,
    required this.needsAttention,
    this.message,
    this.carId,
    this.pendingReview = false,
  });

  final String draftId;
  final bool success;

  /// True when the failure is permanent (validation/auth/rejected media) —
  /// the draft needs the user's attention; it will not be retried
  /// automatically. False (with [success] also false) means the failure
  /// was transient and a background retry is already scheduled.
  final bool needsAttention;
  final String? message;
  final String? carId;
  final bool pendingReview;
}

int _mediaListLength(dynamic v) => v is List ? v.length : 0;

/// E-fix (real-device evidence): a `retryable` record used to be retried
/// unconditionally on every single [PendingSellSubmissionService.resumeAll]
/// trigger (app bootstrap, lifecycle resume, connectivity restore) forever
/// -- with no cap and no minimum spacing between attempts -- which is
/// exactly what a real device observed: the "Uploading listing… 0 of N
/// media uploaded" banner reappearing on every app launch indefinitely,
/// because the underlying condition (e.g. a backend that keeps failing the
/// same way) never actually changes between attempts. Once a record has
/// been retried this many times, treat it as permanent instead of
/// retrying forever -- the user can still fix/retry it manually from My
/// Listings.
const int kSellSubmissionMaxAutoRetryAttempts = 6;

/// Minimum spacing between automatic retry attempts for a `retryable`
/// record, keyed by how many attempts have already been made -- simple
/// exponential backoff capped at 5 minutes, so overlapping triggers close
/// together (startup + connectivity-restore + lifecycle-resume all firing
/// within seconds of each other) don't hammer the backend with the exact
/// same failing request repeatedly.
Duration sellSubmissionRetryBackoff(int attempts) {
  final capped = attempts.clamp(0, 5);
  final seconds = 10 * (1 << capped); // 10s, 20s, 40s, 80s, 160s, 320s
  return Duration(seconds: seconds.clamp(10, 300));
}

/// Test-only override for [sellSubmissionRetryBackoff] -- real backoff
/// delays (seconds to minutes) are impractical to exercise with actual
/// wall-clock waits in a unit test. Tests that are not specifically about
/// backoff timing should set this to `(_) => Duration.zero` in `setUp()`
/// (matching this file's pre-existing zero-delay-between-resumes
/// semantics); tests that ARE about backoff/cap behavior can set it to a
/// large fixed [Duration] to deterministically prove a too-soon retry is
/// skipped, without waiting. Must be reset to `null` in `tearDown()`.
@visibleForTesting
Duration Function(int attempts)? debugSellSubmissionRetryBackoffOverride;

/// Opaque account id for the currently signed-in session, or `''` when
/// unknown (no session, or the profile hasn't loaded yet — see
/// `AuthGuard`'s optimistic render). Not a secret: the same id already
/// visible in every authenticated API response. Used only to stop a
/// submission recorded under one account from being auto-resumed under a
/// different one on a shared device (see [SellSubmissionRecord.ownerUserId]).
String _currentAccountId() =>
    (AuthService().currentUser?['id'] ?? '').toString().trim();

/// F-11-style classification (mirrors `isRetryableChatSendError` /
/// `SellListingMediaUpload._isTransientUploadError`): transient
/// network/transport/server-hiccup errors are safe to retry automatically;
/// everything else (validation, auth, permission, rejected media) is a
/// permanent failure the user must act on.
bool isRetryableSellSubmissionError(Object error) {
  if (error is _ServerTranscodeStillInProgressException) return true;
  if (error is TimeoutException) return true;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 408 ||
        code == 429 ||
        code == 500 ||
        code == 502 ||
        code == 503 ||
        code == 504;
  }
  return isTransientNetworkError(error);
}

/// Phase 3B test-hardening fix: thrown by [PendingSellSubmissionService.
/// _runSubmission] when [SellListingMediaUpload.uploadForCar] returns
/// (normally, no exception) while one or more `server_transcode_videos`
/// entries have not yet reached `attached`. This is expected and NORMAL
/// -- a single run only advances each video's resumable state machine as
/// far as it can get in one call (see `SellServerTranscodeVideoRunner`'s
/// doc comment); a transient hiccup on just one poll/finalize call is
/// captured as durable per-video state, not as a thrown exception, so
/// `uploadForCar` never throws for it on its own.
///
/// Before this fix, `_runSubmission` had no such check at all: it
/// unconditionally treated the whole submission as `done` and deleted
/// this draft's ENTIRE durable record (including every other video's
/// per-video progress, since `serverTranscodeVideos` is nested inside the
/// same [SellSubmissionRecord]) the instant `uploadForCar` returned --
/// even with a video still mid-pipeline. That permanently stranded that
/// video: no later `resumeAll()` could ever find it again, yet the user
/// still saw a successful "listing created" result. Images already guard
/// the equivalent case (see the `if (imagesCount > 0 && '
/// '!listingMediaConfirmed)` retry-then-throw block below); this gives
/// server-transcode videos the same guarantee.
///
/// Always classified `retryable` (never `needsAttention`): the runner's
/// own durable state means a later automatic `resumeAll()` -- subject to
/// the same backoff as any other retryable record -- can pick up exactly
/// where this attempt left off with zero duplicate network calls, so
/// this must never require manual user action.
class _ServerTranscodeStillInProgressException implements Exception {
  const _ServerTranscodeStillInProgressException();

  @override
  String toString() =>
      'Video is still being processed on the server; it will finish '
      'automatically.';
}

/// Application-level coordinator that owns creating the listing and
/// uploading its media once the user presses Submit — deliberately NOT
/// owned by `SellStep5`'s `State` (see `sell_step5_logic.dart`), so:
///   - navigating away from the Sell screen does not cancel the work
///     (nothing here ever checks a widget's `mounted`);
///   - the same in-flight/durably-recorded submission can be resumed from
///     app startup, `AppLifecycleState.resumed`, connectivity recovery, or
///     login completion, without the user reopening the draft or pressing
///     Submit again.
///
/// Responsibilities (single instance, process-wide):
///   - discover pending submissions ([resumeAll])
///   - ensure only one worker runs per draft ([_activeRuns])
///   - create/reuse the backend listing (idempotency key keyed by draftId)
///   - upload remaining images/videos/damage photos
///     ([SellListingMediaUpload] already re-queries the listing's current
///     media count before uploading, so a resumed run never re-uploads
///     media the server already has)
///   - persist progress after every checkpoint ([SellSubmissionStatePrefs])
///   - retry recoverable failures, but mark permanent ones
///     `needsAttention` instead of retrying forever
///   - clean up durable pending-upload media once done
class PendingSellSubmissionService {
  PendingSellSubmissionService._();

  static final PendingSellSubmissionService instance =
      PendingSellSubmissionService._();

  /// Latest progress for whichever submission is actively running "right
  /// now" in this process (null when nothing is actively uploading). A
  /// global banner widget listens to this for the
  /// "Uploading listing… X of Y media uploaded" message.
  final ValueNotifier<SellSubmissionUiStatus?> statusNotifier =
      ValueNotifier<SellSubmissionUiStatus?>(null);

  final StreamController<SellSubmissionEvent> _controller =
      StreamController<SellSubmissionEvent>.broadcast();

  /// One-shot terminal events (success / needs-attention / retry-scheduled)
  /// for a global snackbar/banner, independent of any specific page.
  Stream<SellSubmissionEvent> get events => _controller.stream;

  /// draftId -> in-flight run, so a second trigger (resumeAll firing while
  /// the Submit button's own call is still running, or two resumeAll
  /// triggers firing close together) joins the existing run instead of
  /// starting a duplicate worker for the same draft.
  final Map<String, Future<SellListingSubmitResult?>> _activeRuns = {};

  bool _bulkResumeRunning = false;
  bool _connectivityHooked = false;

  bool isSubmitting(String draftId) => _activeRuns.containsKey(draftId);

  void _emit(SellSubmissionEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }

  /// Begin listening for connectivity coming back online and resume any
  /// durable pending submissions when it does. Safe to call more than once
  /// (only hooks once). Mirrors
  /// `OutgoingChatSendService.hookConnectivityRecovery`.
  void hookConnectivityRecovery() {
    if (_connectivityHooked) return;
    _connectivityHooked = true;
    var wasOnline = ConnectivityService.instance.isOnline.value;
    ConnectivityService.instance.isOnline.addListener(() {
      final isOnline = ConnectivityService.instance.isOnline.value;
      if (isOnline && !wasOnline) {
        unawaited(resumeAll());
      }
      wasOnline = isOnline;
    });
  }

  /// True once the backend listing exists for [draftId] (create step done),
  /// used by the Sell UI to decide whether it is still safe to let the user
  /// resume editing the same draft after a failure (once a listing exists,
  /// the "draft" is this in-progress submission, not editable form state).
  Future<bool> hasCreatedListing(String draftId) async {
    final r = await SellSubmissionStatePrefs.load(draftId);
    return (r?.carId ?? '').trim().isNotEmpty;
  }

  Future<SellSubmissionRecord?> peek(String draftId) =>
      SellSubmissionStatePrefs.load(draftId);

  /// Shared by [submit] and [submitFast]: durably records that this draft
  /// is now being submitted (before any network call), copying any
  /// still-local media into durable app-controlled storage (no-op for
  /// media that is already durable — see `SellDraftMediaPersistence`).
  /// Returns the freshly-upserted record; callers decide separately how to
  /// wait for the resulting worker.
  Future<SellSubmissionRecord> _prepareSubmissionRecord({
    required String draftId,
    required Map<String, dynamic> carData,
    String? editListingId,
  }) async {
    final id = draftId.trim().isEmpty ? 'default' : draftId.trim();

    // Media durability (req. #8): copy any still-local/cache picker files
    // into durable app storage now, synchronously with the Submit press —
    // before the first network call, not after — so a kill mid-create or
    // mid-upload can never lose the source files. No-op for media that is
    // already durable (server URL, or already under the draft's durable
    // folder).
    final durableCarData = await SellDraftMediaPersistence
        .prepareCarDataForStorage(carData, draftId: id);
    final safeCarData = sellSubmissionJsonSafeCarData(durableCarData);

    final existing = await SellSubmissionStatePrefs.load(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final trimmedEditId = editListingId?.trim();
    final resolvedEditId = (trimmedEditId?.isNotEmpty ?? false)
        ? trimmedEditId
        : existing?.editListingId;
    final totalMedia = _mediaListLength(safeCarData['images']) +
        _mediaListLength(safeCarData['videos']) +
        _mediaListLength(safeCarData['damage_images']) +
        _mediaListLength(safeCarData['server_transcode_videos']);
    // Account isolation: stamp the CURRENT account as this draft's owner
    // once, the first time Submit is pressed for it, and never overwrite
    // it on a later resubmit/resume of the SAME draft — otherwise a
    // resume triggered while a *different* account happens to be signed
    // in (see the guard in [_runSubmission]) could re-stamp ownership
    // instead of correctly refusing to run.
    final ownerUserId = existing?.ownerUserId ??
        (_currentAccountId().isEmpty ? null : _currentAccountId());

    final record = SellSubmissionRecord(
      draftId: id,
      status: SellSubmissionStatus.pending,
      isEdit: (resolvedEditId ?? '').trim().isNotEmpty,
      editListingId: resolvedEditId,
      carId: existing?.carId ??
          ((resolvedEditId ?? '').trim().isNotEmpty ? resolvedEditId : null),
      pendingReview: existing?.pendingReview ?? false,
      carData: safeCarData,
      idempotencyKey: existing?.idempotencyKey ??
          SellPendingMediaPrefs.createIdempotencyKey(id),
      currentPhase: existing?.currentPhase ?? 'creating',
      ownerUserId: ownerUserId,
      completedMediaCount: existing?.completedMediaCount ?? 0,
      totalMediaCount: totalMedia,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await SellSubmissionStatePrefs.upsert(record);
    return record;
  }

  /// Called once when the user presses Submit. Durably records that this
  /// draft is now being submitted (before any network call), copies any
  /// still-local media into durable app-controlled storage (no-op for
  /// media that is already durable — see `SellDraftMediaPersistence`), then
  /// starts (or joins) the worker for this draft.
  ///
  /// The returned Future resolves when the ENTIRE submission finishes —
  /// listing create AND every image/video (including a `requiresServer
  /// Transcode` video's full sign->upload->finalize->poll->attach
  /// pipeline, which can take 60-120s). Callers may await it for the
  /// "stay on this page until everything is done" UX, but the underlying
  /// work is NOT cancelled if the caller stops awaiting (e.g. the widget
  /// that called this is disposed because the user navigated away).
  ///
  /// Prefer [submitFast] for the Sell UI's Submit button — see its doc
  /// comment. This method's full-completion contract is kept unchanged
  /// (and still exercised by the existing `pending_sell_submission_service
  /// _test.dart` suite) for any caller that genuinely needs to wait for
  /// media to finish.
  Future<SellListingSubmitResult?> submit({
    required String draftId,
    required Map<String, dynamic> carData,
    String? editListingId,
    void Function(SellSubmissionPhase phase)? onPhase,
  }) async {
    final record = await _prepareSubmissionRecord(
      draftId: draftId,
      carData: carData,
      editListingId: editListingId,
    );
    return _ensureRunning(record.draftId, onPhase: onPhase);
  }

  /// Per-draftId signals resolved by [_runSubmission] the moment the
  /// backend listing itself exists (create succeeded, or already existed
  /// from an earlier attempt) — see [submitFast]. A list (not a single
  /// `Completer`) because more than one [submitFast] caller could in
  /// principle be waiting on the SAME draft at once (e.g. a rapid
  /// double-press before the Submit button's own `isSubmitting` guard
  /// disables it); every registered signal for a draftId is resolved (or
  /// rejected) together, exactly once.
  final Map<String, List<Completer<SellListingSubmitResult>>>
      _carReadySignals = {};

  Completer<SellListingSubmitResult> _registerCarReadySignal(String draftId) {
    final c = Completer<SellListingSubmitResult>();
    (_carReadySignals[draftId] ??= <Completer<SellListingSubmitResult>>[])
        .add(c);
    return c;
  }

  void _resolveCarReadySignals(String draftId, SellListingSubmitResult result) {
    final signals = _carReadySignals.remove(draftId);
    if (signals == null) return;
    for (final c in signals) {
      if (!c.isCompleted) c.complete(result);
    }
  }

  void _rejectCarReadySignals(String draftId, Object error, StackTrace st) {
    final signals = _carReadySignals.remove(draftId);
    if (signals == null) return;
    for (final c in signals) {
      if (!c.isCompleted) c.completeError(error, st);
    }
  }

  /// Fast-return variant of [submit] for the Sell UI's "optimistic
  /// submission" flow.
  ///
  /// Behaves identically to [submit] for every durable-record/
  /// idempotency/resume guarantee — it is the SAME underlying worker
  /// ([_ensureRunning]/[_runSubmission]); the full media pipeline
  /// (image/video upload, and any `requiresServerTranscode` video's
  /// 60-120s server-side transcode) keeps running to completion in the
  /// background exactly as before, unaffected by whether/how long this
  /// method's caller keeps awaiting the Future it returns.
  ///
  /// The difference is only WHEN the returned Future resolves: as soon as
  /// the backend listing record itself exists (create succeeded, or
  /// already existed from an earlier attempt) — NOT once every image/
  /// video has finished uploading/attaching. This is what lets the Sell
  /// UI navigate to My Listings / show submission success the moment the
  /// listing is safely persisted, without making the user wait on
  /// image/video upload or a long server-side video transcode.
  ///
  /// Returns `null` in the same situations [submit] would (e.g. signed out
  /// between validation and this call). Rethrows only when the listing
  /// itself could never be created (validation/auth/permanent failure
  /// before any carId existed) — the same error [submit] would have
  /// thrown in that case. A failure AFTER the listing exists (e.g. a
  /// video upload permanently failing) is never thrown here — it is
  /// surfaced only via [events]/[statusNotifier], like any other
  /// background media failure, because the seller must still see their
  /// listing succeed and continue past Submit.
  Future<SellListingSubmitResult?> submitFast({
    required String draftId,
    required Map<String, dynamic> carData,
    String? editListingId,
    void Function(SellSubmissionPhase phase)? onPhase,
  }) async {
    final record = await _prepareSubmissionRecord(
      draftId: draftId,
      carData: carData,
      editListingId: editListingId,
    );
    final id = record.draftId;

    final existingCarId = (record.carId ?? '').trim();
    if (existingCarId.isNotEmpty) {
      // Listing already exists from an earlier attempt (retry/resume of a
      // `retryable`/`needsAttention` draft whose create step already
      // succeeded) -- nothing to wait for. Kick off/join the background
      // worker for any remaining media and return immediately.
      unawaited(_ensureRunning(id, onPhase: onPhase));
      return SellListingSubmitResult(
        id: existingCarId,
        pendingReview: record.pendingReview,
      );
    }

    final signal = _registerCarReadySignal(id);
    // Deliberately not awaited directly here -- the worker must keep
    // running in the background regardless of whether/how long this
    // method's caller keeps awaiting the Future this method returns
    // (identical guarantee to [submit]).
    final runFuture = _ensureRunning(id, onPhase: onPhase);
    // Defensive fallback only: `_runSubmission` resolves/rejects `signal`
    // (via `_resolveCarReadySignals`/`_rejectCarReadySignals`) as soon as
    // the create step's outcome is known, which is always well before
    // `runFuture` itself settles. This just guarantees `submitFast` can
    // never hang forever even in a case that never reaches those calls at
    // all (e.g. no auth token -- `_runSubmission` returns `null`
    // immediately without ever attempting to create anything). A no-op
    // once the signal has already been settled the normal way.
    unawaited(runFuture.then((result) {
      if (signal.isCompleted) return;
      if (result != null) {
        signal.complete(result);
      } else {
        signal.completeError(
          ApiException(statusCode: 401, message: 'Authentication required'),
        );
      }
    }, onError: (Object e, StackTrace st) {
      if (!signal.isCompleted) signal.completeError(e, st);
    }));

    return signal.future;
  }

  /// Scans every durably-recorded submission and resumes anything eligible
  /// (`pending` / `inProgress` / `retryable`). Safe to call repeatedly and
  /// concurrently from app bootstrap, `AppLifecycleState.resumed`,
  /// connectivity-restored, and login-completion alike — deduplicated both
  /// at the bulk-scan level ([_bulkResumeRunning]) and per-draft
  /// ([_ensureRunning]), so overlapping triggers can never start two
  /// workers for the same draft (req. #5/#6/G).
  /// Returns true when at least one durably-recorded submission was
  /// eligible and (re)started by this call — best-effort signal for
  /// callers like `MyListingsPage` that want to refresh their listing/draft
  /// list once resumed work lands. Waits for every submission started by
  /// *this* call to finish (success or failure) before returning, mirroring
  /// the old `SellPendingMediaResume.tryResume()` contract; callers that
  /// must not block (lifecycle/connectivity hooks) already wrap this in
  /// `unawaited(...)`.
  /// Architecture fix (real-device evidence, Issue 1 -- "global bulk resume
  /// lock blocks lifecycle recovery"): [_bulkResumeRunning] must ONLY guard
  /// the short enumerate-and-dispatch section below (reading every durable
  /// record off disk and starting/joining a runner for each one) -- never
  /// the full lifetime of the upload runners it dispatches.
  ///
  /// Before this fix, the guard stayed held (via the enclosing `finally`)
  /// until every dispatched runner's Future resolved, which could be
  /// minutes for a large media upload. A real device log showed exactly
  /// this: `bulkResumeRunning=true` / `skipped reason=bulk-resume-already-
  /// running` repeating on every `lifecycle=resumed` trigger while OLDER,
  /// unrelated `inProgress` submissions were still uploading -- meaning a
  /// lifecycle resume could not even enumerate records (let alone start a
  /// DIFFERENT, not-yet-running one) while ANY historical submission was
  /// slow. One slow record must never block another record's recovery.
  ///
  /// [_activeRuns] (keyed per draftId, see [_ensureRunning]) remains the
  /// sole authority for preventing a duplicate runner for the SAME draft --
  /// unchanged by this fix. This flag's only remaining job is to stop two
  /// concurrent [resumeAll] callers from redundantly re-reading/
  /// re-dispatching the same on-disk record list at once; `_ensureRunning`
  /// is synchronous up to (and including) registering the future in
  /// `_activeRuns`, so by the time the loop below finishes, every eligible
  /// record's runner is already dispatched/joined and it is safe to release
  /// the guard immediately, well before any of those runs actually finish.
  Future<bool> resumeAll() async {
    appLog('[SELL RESUME] resumeAll invoked');
    appLog('[SELL RUN] resumeAll called');
    appLog('[SELL RUN] bulkResumeRunning=$_bulkResumeRunning');
    if (_bulkResumeRunning) {
      appLog('[SELL RESUME] skipped reason=bulk-resume-already-running');
      return false;
    }
    _bulkResumeRunning = true;
    List<Future<SellListingSubmitResult?>> dispatched;
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) {
        appLog('[SELL RESUME] skipped reason=no-auth-token');
        return false;
      }
      await _migrateLegacyPendingMediaRecord();
      final records = await SellSubmissionStatePrefs.loadAll();
      appLog('[SELL RESUME] records found=${records.length}');
      appLog('[SELL RUN] startup records=${records.length}');
      final currentOwner = _currentAccountId();
      final started = <Future<SellListingSubmitResult?>>[];
      for (final r in records) {
        appLog(
          '[SELL RESUME] record id=${r.draftId} state=${r.status.name} '
          'carId=${(r.carId ?? '').trim().isEmpty ? 'null' : r.carId}',
        );
        appLog(
          '[SELL RUN] record=${r.draftId} state=${r.status.name} '
          'carId=${(r.carId ?? '').trim().isEmpty ? 'null' : r.carId}',
        );
        appLog(
          '[SELL RUN] restored carId=${(r.carId ?? '').trim().isEmpty ? 'null' : r.carId}',
        );
        appLog(
          '[SELL RUN] restored media count='
          '${_mediaListLength(r.carData['images']) + _mediaListLength(r.carData['videos']) + _mediaListLength(r.carData['damage_images'])}',
        );
        if (r.status == SellSubmissionStatus.completed) {
          appLog('[SELL RESUME] skipped reason=already-completed record=${r.draftId}');
          continue;
        }
        // Permanent failures need the user to reopen the draft — never
        // auto-retried (req. #11).
        if (r.status == SellSubmissionStatus.needsAttention) {
          appLog('[SELL RESUME] skipped reason=needs-attention record=${r.draftId}');
          continue;
        }
        // Account isolation: a submission recorded under a different
        // account than the one currently signed in is not "eligible" for
        // this call at all (see the matching guard in [_runSubmission],
        // which also protects the `submit()` entry point) — excluding it
        // here keeps this call's return value an accurate "was anything
        // for THIS account resumed" signal instead of reporting true for
        // a no-op skip.
        final owner = (r.ownerUserId ?? '').trim();
        appLog(
          '[SELL RESUME] owner current=${currentOwner.isEmpty ? 'null' : currentOwner} '
          'record=${owner.isEmpty ? 'null' : owner}',
        );
        if (owner.isNotEmpty && owner != currentOwner) {
          appLog('[SELL RESUME] skipped reason=owner-mismatch record=${r.draftId}');
          continue;
        }
        appLog('[SELL RESUME] starting record=${r.draftId}');
        // `_ensureRunning` dedupes per-draftId via `_activeRuns` and is
        // synchronous up to that registration -- a record whose runner is
        // already active simply joins the existing Future here instead of
        // starting a duplicate one.
        started.add(_ensureRunning(r.draftId));
      }
      dispatched = started;
    } catch (e, st) {
      logNonFatal(e, st, 'PendingSellSubmissionService.resumeAll');
      return false;
    } finally {
      // Released right after enumeration/dispatch -- NOT after the awaited
      // upload work below -- so a concurrent/later `resumeAll()` trigger
      // (another lifecycle resume, connectivity restore, or a fresh manual
      // Submit) can immediately enumerate and start/join whatever it needs,
      // even while every record dispatched by THIS call is still uploading.
      _bulkResumeRunning = false;
    }
    if (dispatched.isEmpty) return false;
    try {
      await Future.wait(dispatched, eagerError: false);
    } catch (e, st) {
      // Individual failures already persisted their own retryable/
      // needsAttention state and emitted an [events] entry above; this
      // catch only prevents one draft's error from stopping the bulk
      // scan itself from reporting "something was resumed".
      logNonFatal(e, st, 'PendingSellSubmissionService.resumeAll.wait');
    }
    return true;
  }

  /// One-time migration of the older, narrower `SellPendingMediaPrefs`
  /// record (create-succeeded-but-media-incomplete only) into the richer
  /// [SellSubmissionStatePrefs] model, so this service becomes the single
  /// source of truth going forward. `SellPendingMediaResume.tryResume()` is
  /// kept as a thin delegator (existing call sites: app bootstrap,
  /// `MyListingsPage`, this service's own retryable-error fallback) — see
  /// that file.
  Future<void> _migrateLegacyPendingMediaRecord() async {
    try {
      final legacy = await SellPendingMediaPrefs.load();
      if (legacy == null) return;
      final carId = (legacy['carId'] ?? '').toString().trim();
      if (carId.isEmpty) {
        await SellPendingMediaPrefs.clear();
        return;
      }
      final draftIdRaw = (legacy['draftId'] ?? '').toString().trim();
      final id = draftIdRaw.isEmpty ? 'legacy_$carId' : draftIdRaw;
      final existing = await SellSubmissionStatePrefs.load(id);
      if (existing == null) {
        final rawCarData = legacy['carData'];
        final carData = rawCarData is Map
            ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
            : <String, dynamic>{};
        final now = DateTime.now().millisecondsSinceEpoch;
        await SellSubmissionStatePrefs.upsert(SellSubmissionRecord(
          draftId: id,
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          pendingReview: legacy['pendingReview'] == true,
          carData: carData,
          idempotencyKey: SellPendingMediaPrefs.createIdempotencyKey(id),
          currentPhase: 'photos',
          totalMediaCount: _mediaListLength(carData['images']) +
              _mediaListLength(carData['videos']) +
              _mediaListLength(carData['damage_images']),
          createdAt: now,
          updatedAt: now,
        ));
      }
      await SellPendingMediaPrefs.clear();
    } catch (e, st) {
      logNonFatal(e, st, 'PendingSellSubmissionService.migrateLegacy');
    }
  }

  Future<SellListingSubmitResult?> _ensureRunning(
    String draftId, {
    void Function(SellSubmissionPhase phase)? onPhase,
  }) {
    final existing = _activeRuns[draftId];
    // Bug-2 instrumentation (real-device trace): proves/disproves whether a
    // stale `_activeRuns` entry is refusing to start a fresh runner while
    // the original one is no longer making progress. If `contains=true`
    // appears repeatedly across separate `resumeAll` triggers with no
    // matching `runner end=` in between, the original runner is genuinely
    // stuck (never completed, never threw) rather than merely slow.
    appLog(
      '[SELL RUN] activeRuns contains=${existing != null} record=$draftId',
    );
    if (existing != null) return existing;
    appLog('[SELL RUN] runner start=$draftId');
    final future = _runSubmission(draftId, onPhase: onPhase)
        .then((result) {
          appLog(
            '[SELL RUN] runner end=$draftId reason=${result != null ? 'success' : 'no-op'}',
          );
          return result;
        }, onError: (Object e, StackTrace st) {
          appLog(
            '[SELL RUN] runner end=$draftId reason=error '
            'exception=${e.runtimeType}',
          );
          appLog('[SELL RUN] runner exception=${e.runtimeType}');
          throw e;
        })
        .whenComplete(() {
      _activeRuns.remove(draftId);
    });
    _activeRuns[draftId] = future;
    return future;
  }

  Future<SellListingSubmitResult?> _runSubmission(
    String draftId, {
    void Function(SellSubmissionPhase phase)? onPhase,
  }) async {
    final loaded = await SellSubmissionStatePrefs.load(draftId);
    if (loaded == null) {
      appLog('[SELL RESUME] skipped reason=no-record record=$draftId');
      return null;
    }
    if (loaded.status == SellSubmissionStatus.needsAttention) {
      appLog('[SELL RESUME] skipped reason=needs-attention record=$draftId');
      return null;
    }
    // Rebind as a non-nullable local: this is reassigned at each
    // checkpoint below, including inside the `catch` block on failure, and
    // a `SellSubmissionRecord?`-typed variable loses its null-check
    // promotion across those reassignments/control-flow joins.
    SellSubmissionRecord record = loaded;

    final token = ApiService.accessToken;
    if (token == null || token.isEmpty) {
      // Cannot proceed without auth. Leave the record as-is; the next
      // login-completion trigger (see `app_with_deep_links.dart`) retries.
      appLog('[SELL RESUME] skipped reason=no-auth-token record=$draftId');
      return null;
    }

    // Account isolation: never finish a submission recorded under one
    // account while a DIFFERENT account is currently signed in (e.g. on a
    // shared device — User A presses Submit, force-quits before it
    // finishes or hits a retryable error, signs out; User B signs in on
    // the same device before User A's record has resolved). Leave the
    // record untouched — it resumes correctly once the ORIGINAL owner
    // signs back in and a resume trigger fires again. Records with no
    // known owner (rare — profile hadn't loaded at Submit time) are not
    // blocked here, matching behavior before this field existed.
    final recordOwner = (record.ownerUserId ?? '').trim();
    if (recordOwner.isNotEmpty) {
      final currentOwner = _currentAccountId();
      appLog(
        '[SELL RESUME] owner current=${currentOwner.isEmpty ? 'null' : currentOwner} '
        'record=$recordOwner',
      );
      if (currentOwner.isEmpty || currentOwner != recordOwner) {
        appLog(
          'PendingSellSubmissionService: skipping $draftId -- owned by a '
          'different account than the one currently signed in',
        );
        appLog('[SELL RESUME] skipped reason=owner-mismatch record=$draftId');
        return null;
      }
    }

    int nowMs() => DateTime.now().millisecondsSinceEpoch;

    // E-fix (real-device evidence): stop retrying a `retryable` record
    // forever. Once it has already been attempted
    // [kSellSubmissionMaxAutoRetryAttempts] times, treat it as permanent
    // instead of letting every future app launch/lifecycle-resume/
    // connectivity-restore trigger retry the exact same failing request
    // again -- this is the "banner stuck at 0 of N across restarts,
    // forever" symptom. `needsAttention` records are already excluded
    // from [resumeAll], so this alone stops the loop.
    if (record.status == SellSubmissionStatus.retryable &&
        record.attempts >= kSellSubmissionMaxAutoRetryAttempts) {
      final exhausted = record.copyWith(
        status: SellSubmissionStatus.needsAttention,
        updatedAt: nowMs(),
      );
      await SellSubmissionStatePrefs.upsert(exhausted);
      logNonFatal(
        StateError(
          'Sell submission $draftId exceeded '
          '$kSellSubmissionMaxAutoRetryAttempts auto-retry attempts '
          '(lastError: ${exhausted.lastErrorMessage})',
        ),
        StackTrace.current,
        'PendingSellSubmissionService.retryExhausted',
      );
      _emit(SellSubmissionEvent(
        draftId: draftId,
        success: false,
        needsAttention: true,
        message: exhausted.lastErrorMessage,
        carId: (exhausted.carId?.trim().isNotEmpty ?? false)
            ? exhausted.carId
            : null,
      ));
      appLog('[SELL RESUME] needsAttention record=$draftId reason=retry-exhausted');
      appLog('[SELL RESUME] skipped reason=retry-exhausted record=$draftId');
      return null;
    }
    // E-fix: minimum spacing between automatic retries of the SAME record
    // (exponential backoff), so overlapping triggers close together
    // (startup + connectivity-restore + lifecycle-resume within seconds of
    // each other -- req. F) don't all immediately retry the same
    // still-failing request; a later trigger picks it up once the backoff
    // window has elapsed. `pending`/`inProgress` records (first attempt,
    // or interrupted mid-run) are never delayed by this.
    if (record.status == SellSubmissionStatus.retryable) {
      final backoffFn =
          debugSellSubmissionRetryBackoffOverride ?? sellSubmissionRetryBackoff;
      final backoff = backoffFn(record.attempts);
      final elapsed = Duration(milliseconds: nowMs() - record.updatedAt);
      if (elapsed < backoff) {
        appLog(
          '[SELL RESUME] skipped reason=backoff-not-elapsed record=$draftId '
          '(elapsed=${elapsed.inSeconds}s < backoff=${backoff.inSeconds}s)',
        );
        return null;
      }
    }

    final carData = Map<String, dynamic>.from(record.carData);
    final imagesCount = _mediaListLength(carData['images']);
    final videosCount = _mediaListLength(carData['videos']);
    final damageCount = _mediaListLength(carData['damage_images']);
    final serverTranscodeCount =
        _mediaListLength(carData['server_transcode_videos']);
    final totalMedia = record.totalMediaCount > 0
        ? record.totalMediaCount
        : imagesCount + videosCount + damageCount + serverTranscodeCount;
    appLog('[SELL RUN] restored media count=$totalMedia');
    appLog('[SELL RUN] media expected=$totalMedia');

    // Bug-2/3 instrumentation (real-device trace, "IMPORTANT DATA
    // DURABILITY CHECK"): counts how many of this record's genuinely
    // local (not-yet-uploaded) media references still point at a readable
    // file right now, out of how many local references exist in total.
    // Anything already durable-server-side (http(s)/uploads/static) is
    // excluded from the denominator -- this is specifically about local
    // sources that could have depended on a non-durable (cache/temp/
    // content://-permission) path disappearing.
    final localSourceCounts = await _localMediaSourceCounts(
      carData,
      draftId: draftId,
    );
    appLog(
      '[SELL RUN] restored local sources existing='
      '${localSourceCounts.existing}/${localSourceCounts.total}',
    );

    // E-fix: a required LOCAL media file that no longer exists (app
    // storage cleared, durable copy deleted out from under a resumed
    // draft, etc.) can never succeed no matter how many times it's
    // retried -- fail closed to `needsAttention` immediately instead of
    // silently dropping the file or retrying forever. Retained server
    // references (already-uploaded URLs/paths) are untouched by this
    // check; only genuinely local, not-yet-uploaded media is examined.
    final missingLocalMedia = await _firstUnreachableLocalMediaPath(
      carData,
      draftId: draftId,
    );
    if (missingLocalMedia != null) {
      final failed = record.copyWith(
        status: SellSubmissionStatus.needsAttention,
        lastErrorMessage:
            'Local media file is no longer available: $missingLocalMedia',
        lastErrorRetryable: false,
        updatedAt: nowMs(),
      );
      await SellSubmissionStatePrefs.upsert(failed);
      _emit(SellSubmissionEvent(
        draftId: draftId,
        success: false,
        needsAttention: true,
        message: failed.lastErrorMessage,
        carId: (failed.carId?.trim().isNotEmpty ?? false)
            ? failed.carId
            : null,
      ));
      appLog('[SELL RESUME] needsAttention record=$draftId reason=missing-local-media');
      appLog('[SELL RESUME] skipped reason=missing-local-media record=$draftId');
      return null;
    }

    appLog('[SELL RESUME] starting record=$draftId');
    record = record.copyWith(
      status: SellSubmissionStatus.inProgress,
      attempts: record.attempts + 1,
      updatedAt: nowMs(),
      clearLastError: true,
    );
    await SellSubmissionStatePrefs.upsert(record);
    appLog(
      '[SELL RUN] persisted progress=${record.completedMediaCount}/'
      '${record.totalMediaCount} status=${record.status.name} '
      'record=$draftId',
    );

    // Issue-2 fix (real-device evidence: "persisted progress incorrectly
    // resets to 0/N"): tracks whichever phase is currently being reported,
    // purely so [_persistProgress] below can include an accurate phase in
    // the UI status it also refreshes -- correctness of progress
    // durability never depends on this, only display.
    var currentUiPhase = SellSubmissionPhase.creating;
    // Declared here (before [reportPhase]/[persistProgress], both of which
    // close over it) rather than down near the media-upload section below
    // -- Dart resolves a local variable by lexical position, so a closure
    // defined earlier in this method could not otherwise see it.
    var completedSoFar = 0;

    void reportPhase(SellSubmissionPhase phase, {required int completed}) {
      currentUiPhase = phase;
      onPhase?.call(phase);
      statusNotifier.value = SellSubmissionUiStatus(
        draftId: draftId,
        phase: phase,
        completedMediaCount: completed,
        totalMediaCount: totalMedia,
      );
      appLog(
        '[SELL RUN] UI progress=$completed/$totalMedia phase=${phase.name} '
        'record=$draftId',
      );
    }

    // Issue-2 fix: durably persists [completed] as this record's
    // `completedMediaCount` the moment it is known, instead of only ever
    // tracking it in an in-memory local variable that was discarded on
    // failure. Called after EVERY confirmed successful server operation
    // (listing image attach/upload, video upload, damage image
    // attach/upload -- see the `onMediaConfirmed` callback wired into
    // `SellListingMediaUpload.uploadForCar` below), so a crash/kill/
    // exception at any point afterward finds the LAST confirmed count on
    // disk, never 0 -- and the `catch` block below never overwrites this
    // with zero, since `record.copyWith(...)` there omits
    // `completedMediaCount` and therefore preserves whatever `record`
    // (reassigned here) already holds.
    Future<void> persistProgress(int completed) async {
      if (completed <= completedSoFar) return;
      completedSoFar = completed;
      record = record.copyWith(completedMediaCount: completed, updatedAt: nowMs());
      // Phase 3B test-hardening fix: `record` is a snapshot captured once
      // earlier in this method and never otherwise refreshed, but
      // `SellServerTranscodeVideoRunner` persists each video's progress
      // into this SAME draft's `serverTranscodeVideos` map independently
      // (its own fresh-read/merge/write cycle -- see `_saveState`) WHILE
      // `uploadForCar` above is still running/just returned. Blindly
      // upserting the stale snapshot here -- which almost always fires
      // via `onMediaConfirmed` right after a server-transcode video makes
      // progress, since that's exactly when a positive `completed` delta
      // shows up -- would silently roll back that already-durable
      // per-video progress the instant this call lands. Re-merge the
      // freshest on-disk value for that one field immediately before
      // writing, so this function's own job (persisting
      // `completedMediaCount`) never regresses a DIFFERENT field it
      // doesn't own.
      final freshestForMerge = await SellSubmissionStatePrefs.load(draftId);
      if (freshestForMerge != null) {
        record = record.copyWith(
          serverTranscodeVideos: freshestForMerge.serverTranscodeVideos,
        );
      }
      await SellSubmissionStatePrefs.upsert(record);
      appLog(
        '[SELL RUN] persisted progress=$completed/$totalMedia '
        'status=${record.status.name} record=$draftId',
      );
      statusNotifier.value = SellSubmissionUiStatus(
        draftId: draftId,
        phase: currentUiPhase,
        completedMediaCount: completed,
        totalMediaCount: totalMedia,
      );
    }

    var carId = (record.carId ?? '').trim();
    // D-fix (real-device evidence): remember whether this run is resuming
    // an already-created listing (vs. creating one for the first time in
    // THIS attempt), so the media-upload progress baseline below can
    // reflect media the server already has instead of always starting the
    // "X of Y media uploaded" banner back at 0 on every resume.
    final carIdAlreadyExisted = carId.isNotEmpty;
    var pendingReview = record.pendingReview;

    try {
      if (carId.isEmpty) {
        reportPhase(SellSubmissionPhase.creating, completed: 0);
        final editId = record.editListingId?.trim() ?? '';
        if (record.isEdit && editId.isNotEmpty) {
          await ApiService.updateCar(
            editId,
            buildSellCarUpdatePayload(carData),
          );
          carId = editId;
          try {
            final fresh = await ApiService.getCar(carId);
            final inner = fresh['car'];
            if (inner is Map) {
              pendingReview = isListingPendingReview(
                Map<String, dynamic>.from(inner.cast<String, dynamic>()),
              );
            }
          } catch (e, st) {
            logNonFatal(e, st);
          }
        } else {
          // Small optimization (safe/idempotent): pre-stage local photos to
          // storage so create->attach is one small call instead of a big
          // multipart upload landing right after create.
          try {
            await SellPhotoPrestage.stageCarData(carData, draftId: draftId);
          } catch (e, st) {
            logNonFatal(e, st);
          }
          final payload = buildSellCarCreatePayload(carData);
          Map<String, dynamic> created;
          try {
            created = await _createCarWithBoundedRetry(
              payload,
              record.idempotencyKey,
            );
          } on ApiException catch (e) {
            appLog(
              'PendingSellSubmissionService: create failed for $draftId: '
              '${e.statusCode} - ${e.message}',
            );
            // Fold `body.errors` (field validation details) into the
            // message so the Sell UI's `userErrorText` shows the specific
            // reason instead of a generic message — unchanged from the
            // pre-existing behavior this replaces.
            final body = e.body;
            var msg = e.message;
            if (body != null) {
              final List<dynamic>? errs = (body['errors'] is List)
                  ? List<dynamic>.from(body['errors']!)
                  : null;
              if (errs != null && errs.isNotEmpty) {
                msg = errs.map((err) => err.toString()).join(', ');
              }
            }
            throw ApiException(
              statusCode: e.statusCode,
              message: msg,
              body: e.body,
            );
          }
          final carObj = listing_identity.unwrapCarApiPayload(created);
          carId = listing_identity.listingPrimaryId(carObj);
          pendingReview = isListingPendingReview(carObj);
          unawaited(
            AnalyticsService.trackProductEvent(
              'listing_created',
              metadata: {'listing_id': carId},
            ),
          );
        }
        if (carId.isEmpty) {
          throw Exception('Failed to create listing');
        }
        record = record.copyWith(
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          pendingReview: pendingReview,
          currentPhase: 'photos',
          updatedAt: nowMs(),
        );
        await SellSubmissionStatePrefs.upsert(record);
        appLog(
          '[SELL RUN] persisted progress=${record.completedMediaCount}/'
          '${record.totalMediaCount} status=${record.status.name} '
          'record=$draftId carId=$carId',
        );
        // Fast-submission fix: the listing itself now durably exists --
        // resolve any [submitFast] caller waiting on THIS draftId right
        // now, before any media upload/server-transcode work below even
        // starts. This is the entire mechanism behind [submitFast]
        // returning as soon as the listing is created instead of once
        // every image/video has finished: this call is a no-op unless a
        // [submitFast] caller actually registered a signal for this
        // draftId (see [_registerCarReadySignal]/[_carReadySignals]).
        _resolveCarReadySignals(
          draftId,
          SellListingSubmitResult(id: carId, pendingReview: pendingReview),
        );
        // Matches the pre-existing timing: the legacy draft snapshot/
        // archive entry is cleared as soon as the listing exists (not only
        // once media finishes) so a killed-and-resumed media phase never
        // shows both a "draft" and the new listing at once. Durable draft
        // media itself is kept until upload actually finishes — see
        // [_clearDurableDraftMedia] below — since `carData` above still
        // reads local files from it.
        if (!record.isEdit) {
          unawaited(discardSellDraftById(draftId));
        }
      }

      // D-fix / Issue-2 fix (crash-window follow-up): on a resumed run
      // (listing already existed before this attempt -- true for EVERY
      // edit-mode submission from its very first attempt, and for any
      // create-mode submission resumed after an interruption), fetch
      // current server media and reconcile confirmed progress from SERVER
      // state BEFORE continuing any media upload work -- never trust the
      // locally-persisted `completedMediaCount` alone, since a process
      // kill between a confirmed server attach and this record's own
      // `persistProgress()` call would otherwise leave it stale (e.g.
      // server truly has 3/5 confirmed, local record still says 1/5 from
      // before the crash). `confirmedServerMediaCount` uses the SAME
      // per-item identity semantics (`ListingImageMedia.id`, then a
      // same-kind source match) that `uploadForCar`'s own
      // `_dropAlreadyAttached`/already-attached-skip logic uses, so
      // reconciliation can never disagree with what upload actually
      // treats as "already there" -- and it only ever counts items THIS
      // submission's own `carData` describes, so it can't be inflated by
      // unrelated/pre-existing edit-mode media on the same car. This
      // baseline is durably PERSISTED immediately (via `persistProgress`,
      // which is itself monotonic -- see its doc comment -- so a lower
      // reconciliation can never erase real, already-persisted progress,
      // e.g. from a local file having since disappeared), so "process
      // restart reconstructs progress from server state" holds even if
      // the process is killed again immediately after this resume starts.
      if (carIdAlreadyExisted && totalMedia > 0) {
        final confirmed = await SellListingMediaUpload.confirmedServerMediaCount(
          carId: carId,
          carData: carData,
        );
        appLog(
          '[SELL RUN] media attached=$confirmed (server-confirmed on '
          'resume) record=$draftId carId=$carId',
        );
        if (confirmed > 0) {
          await persistProgress(confirmed);
          reportPhase(
            SellSubmissionPhase.uploadingPhotos,
            completed: completedSoFar,
          );
        }
      }
      final listingMediaConfirmed = await SellListingMediaUpload.uploadForCar(
        carId: carId,
        carData: carData,
        draftId: draftId,
        multipartFileBuilder: buildVideoMultipartFile,
        onPhase: (phase) {
          switch (phase) {
            case SellMediaUploadPhase.photos:
              reportPhase(
                SellSubmissionPhase.uploadingPhotos,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.videos:
              reportPhase(
                SellSubmissionPhase.uploadingVideos,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.damagePhotos:
              reportPhase(
                SellSubmissionPhase.uploadingDamagePhotos,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.serverTranscodeUploading:
              reportPhase(
                SellSubmissionPhase.uploadingVideoSource,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.serverTranscodeProcessing:
              reportPhase(
                SellSubmissionPhase.processingVideoOnServer,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.serverTranscodeFinishing:
              reportPhase(
                SellSubmissionPhase.finishingVideoUpload,
                completed: completedSoFar,
              );
          }
        },
        // Issue-2 fix: called after EVERY confirmed successful server
        // operation (listing image attach/upload, video upload, damage
        // image attach/upload) with how many NEW items that operation just
        // confirmed -- durably persisted immediately (awaited, not
        // fire-and-forget), so a failure/kill right after still finds the
        // accurate attached count on disk, never 0.
        onMediaConfirmed: (delta) async {
          if (delta <= 0) return;
          await persistProgress(completedSoFar + delta);
        },
      );

      if (imagesCount > 0 && !listingMediaConfirmed) {
        var hasMedia = await SellListingMediaUpload.listingAlreadyHasMedia(carId);
        for (var attempt = 0; !hasMedia && attempt < 4; attempt++) {
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          hasMedia = await SellListingMediaUpload.listingAlreadyHasMedia(carId);
        }
        if (!hasMedia) {
          throw StateError(
            'Listing photos did not finish uploading. Please try again.',
          );
        }
      }

      // Phase 3B test-hardening fix: mirror the images check just above
      // for `server_transcode_videos` -- `uploadForCar` returning is NOT
      // proof every transcode video reached `attached` (see
      // `_ServerTranscodeStillInProgressException`'s doc comment above).
      // Checked directly off this record's own durably-persisted
      // per-video state (same source `_attachedServerTranscodeDraftMediaIds`
      // already reads elsewhere in this file), so it reflects exactly
      // what a later `resumeAll()` would also see.
      if (serverTranscodeCount > 0) {
        final transcodeSpecsForCheck = ServerTranscodeVideoSpec.listFromJson(
          carData['server_transcode_videos'],
        );
        final terminalTranscodeCount = await _terminalServerTranscodeCount(
          draftId,
          transcodeSpecsForCheck,
        );
        if (terminalTranscodeCount < transcodeSpecsForCheck.length) {
          throw const _ServerTranscodeStillInProgressException();
        }
      }

      completedSoFar =
          imagesCount + videosCount + damageCount + serverTranscodeCount;
      reportPhase(SellSubmissionPhase.done, completed: completedSoFar);

      try {
        await CarService().getCars(refresh: true);
      } catch (e, st) {
        logNonFatal(e, st);
      }

      await SellSubmissionStatePrefs.remove(draftId);
      if (!record.isEdit) {
        // discardSellDraftById was already called right after create
        // above; media may have taken a while (or several resumes), so
        // call it again here too — idempotent — in case this draft's
        // create step happened in an earlier process/run than this one.
        unawaited(discardSellDraftById(draftId));
        unawaited(_clearDurableDraftMedia(draftId));
      }
      unawaited(AppHaptics.success());
      statusNotifier.value = null;
      _emit(SellSubmissionEvent(
        draftId: draftId,
        success: true,
        needsAttention: false,
        carId: carId,
        pendingReview: pendingReview,
      ));
      appLog('[SELL RESUME] completed record=$draftId carId=$carId');
      return SellListingSubmitResult(id: carId, pendingReview: pendingReview);
    } catch (e, st) {
      statusNotifier.value = null;
      // Fast-submission fix: reject any [submitFast] caller still waiting
      // on THIS draftId -- a no-op if the listing was already created
      // (the signal was already resolved and removed above), which is
      // exactly the "never throw from submitFast after the listing
      // exists" guarantee its doc comment promises: a media-only failure
      // here finds no signal left to reject.
      _rejectCarReadySignals(draftId, e, st);
      final retryable = isRetryableSellSubmissionError(e);
      final statusCode = e is ApiException ? e.statusCode : null;
      final updated = record.copyWith(
        status: retryable
            ? SellSubmissionStatus.retryable
            : SellSubmissionStatus.needsAttention,
        carId: carId.isNotEmpty ? carId : null,
        pendingReview: pendingReview,
        lastErrorMessage: e.toString(),
        lastErrorStatusCode: statusCode,
        lastErrorRetryable: retryable,
        updatedAt: nowMs(),
      );
      await SellSubmissionStatePrefs.upsert(updated);
      appLog(
        '[SELL RUN] persisted progress=${updated.completedMediaCount}/'
        '${updated.totalMediaCount} status=${updated.status.name} '
        'record=$draftId',
      );
      appLog('[SELL RUN] runner exception=${e.runtimeType} record=$draftId');
      // Permanent failures (req. #11): do not infinite-retry, but do not
      // swallow them either — surfaced via Sentry like every other
      // non-fatal, and via [events] for the global "needs attention" UI.
      if (!retryable) {
        logNonFatal(e, st, 'PendingSellSubmissionService.needsAttention');
      }
      _emit(SellSubmissionEvent(
        draftId: draftId,
        success: false,
        needsAttention: !retryable,
        message: e.toString(),
        carId: carId.isEmpty ? null : carId,
      ));
      appLog(
        '[SELL RESUME] ${retryable ? 'retry' : 'needsAttention'} '
        'record=$draftId',
      );
      rethrow;
    }
  }

  /// E-fix helper: true when [file] genuinely cannot be read right now.
  /// Mirrors `SellListingMediaUpload._localUploadFileExists`'s exact
  /// existence check (`File.existsSync()`, falling back to `XFile.length()`
  /// for content:// / sandboxed paths where `dart:io` lies) so this
  /// preflight never flags a file as "missing" that the actual upload
  /// code would have happily read.
  Future<bool> _localMediaFileExists(XFile file) async {
    final path = file.path.trim();
    if (path.isEmpty) return false;
    try {
      if (File(path).existsSync()) return true;
    } catch (e, st) {
      logNonFatal(e, st);
    }
    try {
      final len = await file.length();
      return len > 0;
    } catch (e, st) {
      logNonFatal(e, st);
      return false;
    }
  }

  /// E-fix: scans `images` / `videos` / `damage_images` for the first
  /// entry that is a genuinely LOCAL, not-yet-uploaded reference (per
  /// [ListingImageMedia.localFile] -- already-attached server references
  /// like `http(s)://…`/`uploads/…`/`static/…` are skipped) whose backing
  /// file can no longer be read. Returns that path, or `null` when every
  /// local reference is still readable (including when there are none).
  Future<String?> _firstUnreachableLocalMediaPath(
    Map<String, dynamic> carData, {
    String? draftId,
  }) async {
    for (final key in const ['images', 'videos', 'damage_images']) {
      final raw = carData[key];
      if (raw is! List) continue;
      for (final item in raw) {
        final local = ListingImageMedia.localFile(item);
        if (local == null) continue;
        if (await _localMediaFileExists(local)) continue;
        return local.path;
      }
    }
    // Phase 3B: `server_transcode_videos` entries carry their own
    // `local_source_path` (a `ServerTranscodeVideoSpec`, not a
    // `ListingImageMedia` shape) -- same E-fix fail-closed guard applies:
    // a durably-required source file that has disappeared can never
    // succeed no matter how many times the sign/upload step is retried.
    // Skip any entry already `attached` -- its local source is no longer
    // load-bearing once the server has the final transcoded video.
    final specs = ServerTranscodeVideoSpec.listFromJson(
      carData['server_transcode_videos'],
    );
    if (specs.isNotEmpty) {
      final attachedIds = await _attachedServerTranscodeDraftMediaIds(
        draftId,
        specs,
      );
      for (final spec in specs) {
        if (attachedIds.contains(spec.draftMediaId)) continue;
        if (await _localMediaFileExists(XFile(spec.localSourcePath))) continue;
        return spec.localSourcePath;
      }
    }
    return null;
  }

  /// Phase 3B test-hardening fix support: counts how many of [specs] have
  /// reached a TERMINAL per-video state -- `attached` (succeeded) OR
  /// `failedPermanent` (e.g. rejected/unsupported even server-side) -- per
  /// [ServerTranscodeVideoState.isTerminal]. Deliberately broader than
  /// [_attachedServerTranscodeDraftMediaIds] (which only counts `attached`,
  /// for a different purpose: deciding whether a local source file is
  /// still load-bearing): a permanently-failed video will NEVER become
  /// `attached` no matter how many times it's resumed, so gating overall
  /// submission completion on `attached` alone would retry such a
  /// submission forever. A permanently-failed video must never block the
  /// rest of the listing (same independence guarantee documented on the
  /// normal-video/damage-photo blocks in `sell_listing_media_upload.dart`).
  Future<int> _terminalServerTranscodeCount(
    String? draftId,
    List<ServerTranscodeVideoSpec> specs,
  ) async {
    if (draftId == null || draftId.isEmpty || specs.isEmpty) return 0;
    try {
      final record = await SellSubmissionStatePrefs.load(draftId);
      if (record == null) return 0;
      var count = 0;
      for (final spec in specs) {
        final state = record.serverTranscodeVideos[spec.draftMediaId];
        if (state?.isTerminal ?? false) count++;
      }
      return count;
    } catch (e, st) {
      logNonFatal(
        e,
        st,
        'PendingSellSubmissionService.terminalServerTranscodeCount',
      );
      return 0;
    }
  }

  Future<Set<String>> _attachedServerTranscodeDraftMediaIds(
    String? draftId,
    List<ServerTranscodeVideoSpec> specs,
  ) async {
    if (draftId == null || draftId.isEmpty || specs.isEmpty) return const {};
    try {
      final record = await SellSubmissionStatePrefs.load(draftId);
      if (record == null) return const {};
      final out = <String>{};
      for (final spec in specs) {
        final state = record.serverTranscodeVideos[spec.draftMediaId];
        if (state?.status == ServerTranscodeVideoStatus.attached) {
          out.add(spec.draftMediaId);
        }
      }
      return out;
    } catch (e, st) {
      logNonFatal(e, st, 'PendingSellSubmissionService.attachedServerTranscodeIds');
      return const {};
    }
  }

  /// Bug-2/3 instrumentation: counts every genuinely local (not-yet-
  /// uploaded) media reference across `images` / `videos` /
  /// `damage_images`, and how many of those still have a readable backing
  /// file right now. Purely diagnostic (log-only) -- never mutates
  /// [carData] and never treats a missing file as a reason to drop or
  /// delete anything itself; see [_firstUnreachableLocalMediaPath] for the
  /// actual fail-closed behavior.
  Future<({int existing, int total})> _localMediaSourceCounts(
    Map<String, dynamic> carData, {
    String? draftId,
  }) async {
    var total = 0;
    var existing = 0;
    for (final key in const ['images', 'videos', 'damage_images']) {
      final raw = carData[key];
      if (raw is! List) continue;
      for (final item in raw) {
        final local = ListingImageMedia.localFile(item);
        if (local == null) continue;
        total++;
        if (await _localMediaFileExists(local)) existing++;
      }
    }
    final specs = ServerTranscodeVideoSpec.listFromJson(
      carData['server_transcode_videos'],
    );
    if (specs.isNotEmpty) {
      final attachedIds = await _attachedServerTranscodeDraftMediaIds(
        draftId,
        specs,
      );
      for (final spec in specs) {
        if (attachedIds.contains(spec.draftMediaId)) continue;
        total++;
        if (await _localMediaFileExists(XFile(spec.localSourcePath))) {
          existing++;
        }
      }
    }
    return (existing: existing, total: total);
  }

  // NOTE: server-derived confirmed-media-count reconciliation now lives in
  // `SellListingMediaUpload.confirmedServerMediaCount()` (identity-based --
  // matches per-item against server-attached sources of the same kind,
  // exactly like `uploadForCar`'s own already-attached-skip logic), used
  // from `_runSubmission` above. The old count-only version that lived
  // here was replaced, not duplicated (see the call site's doc comment for
  // the correctness gap it fixed: a raw server-side item COUNT can't tell
  // "N images on the server" apart from "N images on the server, only some
  // of which are actually in THIS carData's list").

  Future<void> _clearDurableDraftMedia(String draftId) async {
    try {
      final dir = await SellDraftMediaPersistence.draftDirectory(draftId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// F-11-style tiny bounded retry (2 attempts total) around the single
  /// `POST /api/cars` create call, reusing the SAME [idempotencyKey] for
  /// every attempt (including every later resumed attempt for this draft —
  /// see [SellSubmissionRecord.idempotencyKey]). Safe because the backend
  /// replays the first successful response for a repeated key within its
  /// TTL (`kk/idempotency.py`), so a retry/resume can never create a second
  /// listing. Only transient network/transport failures are retried;
  /// validation/auth/permission failures surface immediately.
  Future<Map<String, dynamic>> _createCarWithBoundedRetry(
    Map<String, dynamic> payload,
    String idempotencyKey,
  ) async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await ApiService.createCar(
          payload,
          idempotencyKey: idempotencyKey,
        );
      } catch (e) {
        if (!isRetryableSellSubmissionError(e) || attempt >= maxAttempts) {
          rethrow;
        }
        appLog(
          'PendingSellSubmissionService: retrying createCar after '
          'transient error: $e',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError('createCar retry loop exited unexpectedly');
  }
}
