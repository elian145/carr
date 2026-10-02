/// Optimistic-submission fix: merges a listing owner's own still-in-flight
/// local (on-device) Sell submission media into a server-fetched listing
/// map, for OWNER-ONLY display while [PendingSellSubmissionService]'s
/// background media pipeline (image/video upload, and any
/// `requiresServerTranscode` video's server-side transcode) has not yet
/// finished attaching everything server-side.
///
/// Why this exists: with `PendingSellSubmissionService.submitFast()` (see
/// `pending_sell_submission_service.dart`), the Sell UI now navigates to
/// My Listings as soon as the backend listing record itself exists —
/// deliberately WITHOUT waiting for image/video upload or a 60-120s
/// server-side video transcode. Without this merge, the seller would
/// briefly see their own brand-new listing with missing/incomplete media
/// even though they just picked those exact photos/videos seconds ago on
/// this very device. This helper reads the SAME durable
/// [SellSubmissionRecord] the background worker is still advancing
/// (`sell_submission_state_prefs.dart`) and fills in local fallback media
/// for whatever the server does not yet have.
///
/// SAFETY (never leaks a local file to anyone else):
///   - callers MUST pass the correct `isOwner`/only call the "Owned
///     listings" variants for listings that are actually this account's
///     own (`isListingOwner`) -- this module does not itself re-derive
///     identity;
///   - even for the true owner, the merge is a no-op unless a durable
///     [SellSubmissionRecord] for the SAME carId currently exists ON THIS
///     DEVICE (see `SellSubmissionStatePrefs`) -- which is never the case
///     on a different device, or a different account, that never pressed
///     Submit for this listing locally. Nothing here ever performs a
///     network call or reads another draft's/account's data.
///
/// Dedup / no-duplicate-media guarantee: local fallback items are only
/// ever ADDED past however many of this submission's own images/videos
/// the server already confirms it has (never a wholesale replacement of
/// the server's list), and every final list is deduped by
/// [SellDraftMediaPersistence.canonicalMediaIdentity] before being
/// returned. Once the server has ALL of this submission's media, no
/// fallback item is ever added, and merging becomes a no-op again on the
/// next refresh once [SellSubmissionStatePrefs] removes the record
/// entirely (see `PendingSellSubmissionService._runSubmission`'s success
/// path).
library;

import '../../features/sell/sell_server_transcode_video.dart';
import '../prefs/sell_draft_media_persistence.dart';
import '../prefs/sell_submission_state_prefs.dart';
import 'listing_identity.dart';
import 'listing_image_media.dart';

abstract final class OwnerPendingMediaMerge {
  static Future<Map<String, SellSubmissionRecord>> _recordsByCarId() async {
    final all = await SellSubmissionStatePrefs.loadAll();
    final byCarId = <String, SellSubmissionRecord>{};
    for (final r in all) {
      final id = (r.carId ?? '').trim();
      if (id.isNotEmpty) byCarId[id] = r;
    }
    return byCarId;
  }

  static Future<SellSubmissionRecord?> _findRecordForCarId(
    String carId,
  ) async {
    final id = carId.trim();
    if (id.isEmpty) return null;
    final byCarId = await _recordsByCarId();
    return byCarId[id];
  }

  /// Public accessor for [_findRecordForCarId] -- lets other owner-only
  /// media modules (e.g. `owner_media_overlay.dart`'s per-item local/remote
  /// reconciliation) reuse the EXACT SAME durable-record lookup this file's
  /// own [isMediaProcessing]/[mergeIfOwner] use, instead of re-reading
  /// [SellSubmissionStatePrefs] independently. Same safety contract as
  /// every other method here: callers must already know [carId] belongs to
  /// the current account before treating a non-null result as meaningful.
  static Future<SellSubmissionRecord?> recordForCarId(String carId) =>
      _findRecordForCarId(carId);

  /// True while [carId] still has a durable pending-submission record on
  /// THIS device -- i.e. `mediaStatus == processing` in the conceptual
  /// model from the task (`userFacingStatus` stays `submitted`
  /// regardless; only [mediaStatus] toggles once the record is removed).
  /// Used to show a subtle "Processing media" indicator; never used to
  /// gate/block any part of the seller-facing UI.
  static Future<bool> isMediaProcessing(String carId) async {
    return await _findRecordForCarId(carId) != null;
  }

  /// Bulk variant of [isMediaProcessing] for a whole listing page (e.g.
  /// My Listings) -- reads the durable prefs list ONCE instead of once
  /// per card.
  static Future<Set<String>> processingCarIds(
    Iterable<Map<String, dynamic>> cars,
  ) async {
    final byCarId = await _recordsByCarId();
    if (byCarId.isEmpty) return const <String>{};
    final ids = <String>{};
    for (final car in cars) {
      final id = listingPrimaryId(car);
      if (id.isNotEmpty && byCarId.containsKey(id)) ids.add(id);
    }
    return ids;
  }

  /// Returns [car] with local pending images/videos from this device's
  /// durable submission record merged in, for whatever the server does
  /// not yet have attached. No-op (returns [car] unchanged, same instance)
  /// when [isOwner] is false or no matching durable record exists on this
  /// device.
  static Future<Map<String, dynamic>> mergeIfOwner(
    Map<String, dynamic> car, {
    required bool isOwner,
  }) async {
    if (!isOwner) return car;
    final carId = listingPrimaryId(car);
    final record = await _findRecordForCarId(carId);
    if (record == null) return car;
    return _merge(car, record);
  }

  /// Bulk variant of [mergeIfOwner] for a whole listing page. Every
  /// listing in [cars] is assumed to already be owned by the current
  /// account (true for e.g. `GET /api/my-listings` results) -- callers
  /// that mix owned and non-owned listings must use [mergeIfOwner]
  /// per-item instead.
  static Future<List<Map<String, dynamic>>> mergeOwnedListings(
    List<Map<String, dynamic>> cars,
  ) async {
    final byCarId = await _recordsByCarId();
    if (byCarId.isEmpty) return cars;
    final out = <Map<String, dynamic>>[];
    for (final car in cars) {
      final record = byCarId[listingPrimaryId(car)];
      out.add(record == null ? car : _merge(car, record));
    }
    return out;
  }

  static List<dynamic> _dedupeAppend(
    List<dynamic> base,
    List<dynamic> extra,
  ) {
    if (extra.isEmpty) return base;
    final seen = <String>{
      for (final it in base) SellDraftMediaPersistence.canonicalMediaIdentity(it),
    };
    final toAdd = <dynamic>[];
    for (final it in extra) {
      final id = SellDraftMediaPersistence.canonicalMediaIdentity(it);
      if (id.isEmpty || !seen.add(id)) continue;
      toAdd.add(it);
    }
    return toAdd.isEmpty ? base : [...base, ...toAdd];
  }

  static Map<String, dynamic> _merge(
    Map<String, dynamic> car,
    SellSubmissionRecord record,
  ) {
    final merged = Map<String, dynamic>.from(car);
    final pendingCarData = record.carData;

    // ---- Listing images (damage images are never shown in cards/hero;
    // skip merging those here to match the existing owner-facing surfaces
    // this feeds, which already exclude `kind == damage`). ----
    final remoteImages = (car['images'] is List)
        ? List<dynamic>.from(car['images'] as List)
        : const <dynamic>[];
    final remoteListingCount = remoteImages.where((it) {
      final kind = (it is Map ? (it['kind'] ?? 'listing') : 'listing')
          .toString()
          .toLowerCase();
      return kind != 'damage';
    }).length;
    final pendingImages = (pendingCarData['images'] is List)
        ? List<dynamic>.from(pendingCarData['images'] as List)
        : const <dynamic>[];
    final localPendingImages = pendingImages
        .where((it) => ListingImageMedia.localFile(it) != null)
        .toList();
    if (localPendingImages.isNotEmpty &&
        remoteListingCount < localPendingImages.length) {
      // Placeholder-regression fix (real-device evidence): images have
      // no per-item server identity exposed to the client
      // (`CarImage.source_media_id` is internal-bookkeeping-only, never
      // in `to_dict()`), unlike `requiresServerTranscode` videos' exact
      // `draft_media_id`-keyed status below. The previous heuristic
      // ASSUMED local pick order matches server attach order and
      // "skipped" however many of the FIRST local picks the server
      // already reported -- but Phase-A images upload/self-attach
      // concurrently on independent Celery workers and routinely land
      // OUT OF pick order, so that assumption breaks in practice: it can
      // skip (silently drop, showing neither the local nor any remote
      // copy of it) a picked photo that is NOT actually attached yet,
      // while simultaneously duplicating a different photo that IS
      // attached (shown once as the real remote row, once again as a
      // stale local fallback the skip failed to exclude). Never skipping
      // by count -- showing every still-listed local pick unconditionally
      // alongside whatever the server already has -- trades that
      // (permanent, until the seller notices) DROPPED-photo failure mode
      // for, at worst, a brief duplicate thumbnail for whichever pick(s)
      // happen to have already landed; the dedupe pass below still
      // collapses any exact identity match, and the whole fallback
      // disappears on the very next refresh once `remoteListingCount`
      // reaches `localPendingImages.length` (or the durable record is
      // removed entirely on submission success).
      merged['images'] = _dedupeAppend(remoteImages, localPendingImages);
    }

    // ---- Videos: normal videos use the same count-based approximation;
    // `requiresServerTranscode` videos have an EXACT per-item status
    // (`ServerTranscodeVideoState.status`) keyed by `draft_media_id`, so
    // those never rely on any heuristic -- a video is shown locally iff
    // it is durably confirmed NOT YET `attached`. ----
    final remoteVideos = (car['videos'] is List)
        ? List<dynamic>.from(car['videos'] as List)
        : const <dynamic>[];
    final normalPendingVideos = (pendingCarData['videos'] is List)
        ? List<dynamic>.from(pendingCarData['videos'] as List)
        : const <dynamic>[];
    final transcodeSpecs = ServerTranscodeVideoSpec.listFromJson(
      pendingCarData['server_transcode_videos'],
    );
    final transcodeAttachedCount = transcodeSpecs.where((s) {
      return record.serverTranscodeVideos[s.draftMediaId]?.status ==
          ServerTranscodeVideoStatus.attached;
    }).length;
    // Remote video count attributable to "normal" videos only -- exclude
    // already-attached transcoded videos so a still-pending NORMAL video
    // is never mistaken for already-remote just because an unrelated
    // transcoded video happened to land first.
    final remoteNormalCount =
        (remoteVideos.length - transcodeAttachedCount).clamp(0, remoteVideos.length);

    final videoFallback = <dynamic>[];
    if (normalPendingVideos.isNotEmpty &&
        remoteNormalCount < normalPendingVideos.length) {
      // Two-video-regression fix: same reasoning as the images fix
      // above -- a normal video's manifest attach can land out of pick
      // order relative to a sibling normal video (e.g. one fails
      // permanently while another later-picked one succeeds first), so
      // skipping the FIRST `remoteNormalCount` local picks can drop the
      // wrong (still-pending) one. Show every still-listed local pick
      // unconditionally instead; the dedupe pass below still collapses
      // any exact identity match once it is truly remote.
      videoFallback.addAll(normalPendingVideos);
    }
    for (final spec in transcodeSpecs) {
      final attached = record.serverTranscodeVideos[spec.draftMediaId]?.status ==
          ServerTranscodeVideoStatus.attached;
      if (!attached) videoFallback.add(spec.localSourcePath);
    }
    if (videoFallback.isNotEmpty) {
      merged['videos'] = _dedupeAppend(remoteVideos, videoFallback);
    }

    return merged;
  }
}
