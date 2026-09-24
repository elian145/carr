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

  /// Called once when the user presses Submit. Durably records that this
  /// draft is now being submitted (before any network call), copies any
  /// still-local media into durable app-controlled storage (no-op for
  /// media that is already durable — see `SellDraftMediaPersistence`), then
  /// starts (or joins) the worker for this draft.
  ///
  /// The returned Future resolves when this run finishes — callers may
  /// await it for the common "stay on this page" UX, but the underlying
  /// work is NOT cancelled if the caller stops awaiting (e.g. the widget
  /// that called this is disposed because the user navigated away).
  Future<SellListingSubmitResult?> submit({
    required String draftId,
    required Map<String, dynamic> carData,
    String? editListingId,
    void Function(SellSubmissionPhase phase)? onPhase,
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
        _mediaListLength(safeCarData['damage_images']);
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
    return _ensureRunning(id, onPhase: onPhase);
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
  Future<bool> resumeAll() async {
    if (_bulkResumeRunning) return false;
    _bulkResumeRunning = true;
    try {
      final token = ApiService.accessToken;
      if (token == null || token.isEmpty) return false;
      await _migrateLegacyPendingMediaRecord();
      final records = await SellSubmissionStatePrefs.loadAll();
      final currentOwner = _currentAccountId();
      final futures = <Future<SellListingSubmitResult?>>[];
      for (final r in records) {
        if (r.status == SellSubmissionStatus.completed) continue;
        // Permanent failures need the user to reopen the draft — never
        // auto-retried (req. #11).
        if (r.status == SellSubmissionStatus.needsAttention) continue;
        // Account isolation: a submission recorded under a different
        // account than the one currently signed in is not "eligible" for
        // this call at all (see the matching guard in [_runSubmission],
        // which also protects the `submit()` entry point) — excluding it
        // here keeps this call's return value an accurate "was anything
        // for THIS account resumed" signal instead of reporting true for
        // a no-op skip.
        final owner = (r.ownerUserId ?? '').trim();
        if (owner.isNotEmpty && owner != currentOwner) continue;
        futures.add(_ensureRunning(r.draftId));
      }
      if (futures.isEmpty) return false;
      try {
        await Future.wait(futures, eagerError: false);
      } catch (e, st) {
        // Individual failures already persisted their own retryable/
        // needsAttention state and emitted an [events] entry above; this
        // catch only prevents one draft's error from stopping the bulk
        // scan itself from reporting "something was resumed".
        logNonFatal(e, st, 'PendingSellSubmissionService.resumeAll.wait');
      }
      return true;
    } catch (e, st) {
      logNonFatal(e, st, 'PendingSellSubmissionService.resumeAll');
      return false;
    } finally {
      _bulkResumeRunning = false;
    }
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
    if (existing != null) return existing;
    final future = _runSubmission(draftId, onPhase: onPhase).whenComplete(() {
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
    if (loaded == null) return null;
    if (loaded.status == SellSubmissionStatus.needsAttention) return null;
    // Rebind as a non-nullable local: this is reassigned at each
    // checkpoint below, including inside the `catch` block on failure, and
    // a `SellSubmissionRecord?`-typed variable loses its null-check
    // promotion across those reassignments/control-flow joins.
    SellSubmissionRecord record = loaded;

    final token = ApiService.accessToken;
    if (token == null || token.isEmpty) {
      // Cannot proceed without auth. Leave the record as-is; the next
      // login-completion trigger (see `app_with_deep_links.dart`) retries.
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
      if (currentOwner.isEmpty || currentOwner != recordOwner) {
        appLog(
          'PendingSellSubmissionService: skipping $draftId -- owned by a '
          'different account than the one currently signed in',
        );
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
        return null;
      }
    }

    final carData = Map<String, dynamic>.from(record.carData);
    final imagesCount = _mediaListLength(carData['images']);
    final videosCount = _mediaListLength(carData['videos']);
    final damageCount = _mediaListLength(carData['damage_images']);
    final totalMedia = record.totalMediaCount > 0
        ? record.totalMediaCount
        : imagesCount + videosCount + damageCount;

    // E-fix: a required LOCAL media file that no longer exists (app
    // storage cleared, durable copy deleted out from under a resumed
    // draft, etc.) can never succeed no matter how many times it's
    // retried -- fail closed to `needsAttention` immediately instead of
    // silently dropping the file or retrying forever. Retained server
    // references (already-uploaded URLs/paths) are untouched by this
    // check; only genuinely local, not-yet-uploaded media is examined.
    final missingLocalMedia = await _firstUnreachableLocalMediaPath(carData);
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
      return null;
    }

    record = record.copyWith(
      status: SellSubmissionStatus.inProgress,
      attempts: record.attempts + 1,
      updatedAt: nowMs(),
      clearLastError: true,
    );
    await SellSubmissionStatePrefs.upsert(record);

    void reportPhase(SellSubmissionPhase phase, {required int completed}) {
      onPhase?.call(phase);
      statusNotifier.value = SellSubmissionUiStatus(
        draftId: draftId,
        phase: phase,
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

      var completedSoFar = 0;
      // D-fix: on a resumed run (listing already existed before this
      // attempt), reflect whatever media the server already confirmed
      // instead of always reporting "0 of N" while `uploadForCar` below
      // re-discovers and skips the media that already landed. `uploadForCar`
      // itself always re-queries the server before uploading anything, so
      // this is a display-only correction, not a behavior change.
      if (carIdAlreadyExisted && totalMedia > 0) {
        completedSoFar = await _confirmedServerMediaCount(
          carId,
          imagesCount: imagesCount,
          videosCount: videosCount,
          damageCount: damageCount,
        );
        if (completedSoFar > 0) {
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
              completedSoFar += imagesCount;
              reportPhase(
                SellSubmissionPhase.uploadingVideos,
                completed: completedSoFar,
              );
            case SellMediaUploadPhase.damagePhotos:
              completedSoFar += videosCount;
              reportPhase(
                SellSubmissionPhase.uploadingDamagePhotos,
                completed: completedSoFar,
              );
          }
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

      completedSoFar = imagesCount + videosCount + damageCount;
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
      return SellListingSubmitResult(id: carId, pendingReview: pendingReview);
    } catch (e, st) {
      statusNotifier.value = null;
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
    Map<String, dynamic> carData,
  ) async {
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
    return null;
  }

  /// D-fix: how much of [carId]'s expected media (clamped per-bucket to
  /// what THIS draft actually submits, so leftover media from an unrelated
  /// earlier attempt on the same listing never over-reports) is already
  /// confirmed on the server right now. Best-effort — any failure reports
  /// 0 (the pre-existing "assume nothing landed yet" display behavior),
  /// never blocks or fails the actual upload.
  Future<int> _confirmedServerMediaCount(
    String carId, {
    required int imagesCount,
    required int videosCount,
    required int damageCount,
  }) async {
    try {
      final fresh = await ApiService.getCar(carId);
      final inner = fresh['car'];
      final car = inner is Map
          ? Map<String, dynamic>.from(inner.cast<String, dynamic>())
          : fresh;
      var listingImages = 0;
      var damageImages = 0;
      final imgs = car['images'];
      if (imgs is List) {
        for (final it in imgs) {
          final kind = it is Map
              ? (it['kind'] ?? 'listing').toString().toLowerCase()
              : 'listing';
          if (kind == 'damage') {
            damageImages++;
          } else {
            listingImages++;
          }
        }
      }
      final vids = car['videos'];
      final videos = vids is List ? vids.length : 0;
      return listingImages.clamp(0, imagesCount) +
          videos.clamp(0, videosCount) +
          damageImages.clamp(0, damageCount);
    } catch (e, st) {
      logNonFatal(e, st, 'PendingSellSubmissionService.confirmedServerMediaCount');
      return 0;
    }
  }

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
