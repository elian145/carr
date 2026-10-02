/// Owner-optimistic-media fix (task: "I want optimistic local media"):
/// per-item (not just per-listing) local<->remote reconciliation for a
/// listing owner's OWN still-in-flight Sell submission, built on top of
/// [OwnerPendingMediaMerge]'s existing durable-record lookup.
///
/// [OwnerPendingMediaMerge] already lets the owner see their own local
/// photos/videos appended past whatever the server currently has, but only
/// as a flat, whole-list heuristic (see its own doc comment) -- it cannot
/// tell the UI "local file X and remote URL Y are the SAME item, so keep
/// showing X until Y has genuinely finished loading, then swap". This
/// module produces that finer-grained, per-item structure (an ordered list
/// of [OwnerMediaSlot]s, each carrying its own `localPath`/`remoteUrl`
/// pair) so a fallback-aware widget (`OwnerFallbackHeroImage`/
/// `OwnerFallbackVideoThumbnail`) can decide, per tile, whether to render
/// local or remote -- see `car_details_page_media.dart`.
///
/// IDENTITY (Critical Issue 2 fix -- "positional pairing is too weak"):
/// EXACT `client_media_id`-based wherever the server exposes a per-item
/// identity back to the OWNER -- server-transcode videos (via
/// `record.serverTranscodeVideos[draftMediaId]`, unchanged), and now ALSO
/// listing images and normal videos, via the owner-only `client_media_id`
/// field `GET /api/cars/<id>` now includes on each `images[]`/`videos[]`
/// entry (`kk/routes/cars.py::_with_media_compat`/`_serialize_videos`,
/// mirroring `CarImage.source_media_id`/`CarVideo.source_draft_media_id`
/// -- already durably stored at self-attach time, just not previously
/// surfaced). No heuristic pairing whenever both sides have an id: a
/// local item's `clientMediaId` is looked up directly against the
/// server's own `client_media_id` for that image/video, immune to the
/// server returning images in a different order than they were uploaded.
///
/// ORDER-based (this local item is the Nth STILL-UNMATCHED local pick of
/// its kind, paired with the Nth STILL-UNMATCHED remote item of the same
/// kind) ONLY as a fallback for legacy rows that genuinely have no
/// `client_media_id` at all (pre-dates this field, or attached via the
/// older client-driven `/images/attach` path) -- see `_pairByIdThenOrder`.
/// A photo can very rarely show a SIBLING pick's own remote bytes for the
/// brief window before the real (legacy, order-based) pairing settles
/// (all listing photos being of the same car makes this visually
/// unnoticeable), but every expected item ALWAYS ends up genuinely
/// remote-backed once the server has all of them, and one is never
/// permanently dropped or left blank.
///
/// EDIT-MODE SCOPE: only ever produces slots for a NON-edit (new-listing)
/// submission record. An edit-mode record's `carData` can mix newly-added
/// local items with kept-from-before remote items in arbitrary relative
/// order, which breaks the positional-within-kind assumption above far
/// more easily than a fresh listing's "every item is local, in pick
/// order" case -- edit-mode listings keep using
/// [OwnerPendingMediaMerge]'s existing (unchanged) coarse dedupe-append
/// behavior instead.
library;

import '../../features/sell/sell_media_identity.dart';
import '../../features/sell/sell_server_transcode_video.dart';
import '../prefs/owner_optimistic_media_prefs.dart';
import '../prefs/sell_submission_state_prefs.dart';
import 'listing_identity.dart';
import 'listing_image_media.dart';
import 'owner_optimistic_media_cleanup.dart';
import 'owner_pending_media_merge.dart';

/// One remote media entry as returned by the server, carrying its
/// owner-only exact identity when available (`null` for legacy rows --
/// see the file-level doc comment).
typedef _RemoteMediaEntry = ({String? clientMediaId, String url});

enum OwnerMediaKind { image, video }

/// One expected media item's local<->remote pairing, for the OWNER's own
/// in-flight submission. Either [localPath] or [remoteUrl] (never both)
/// may be null/empty, but not both -- see [OwnerMediaOverlay] for when
/// each is populated.
class OwnerMediaSlot {
  const OwnerMediaSlot({
    required this.clientMediaId,
    required this.kind,
    required this.order,
    required this.localPath,
    required this.remoteUrl,
    this.matchedById = false,
  });

  /// Stable per-item id -- see [SellMediaIdentity]/`draft_media_id`. Used
  /// only for debug tracing and as a stable widget key; never sent over
  /// the network from here.
  final String clientMediaId;
  final OwnerMediaKind kind;

  /// Position among this submission's own items of the SAME [kind] (0
  /// listing-image, 1 listing-image, ... 0 video, 1 video, ...) -- the
  /// ordering basis for positional-within-kind remote pairing; see the
  /// file-level doc comment.
  final int order;

  /// Durable local file path (already copied into app storage by
  /// `SellDraftMediaPersistence` well before this ever runs -- see
  /// `PendingSellSubmissionService._prepareSubmissionRecord`), or `null`
  /// if the expected local file could not be resolved (e.g. deleted out
  /// from under a resumed draft -- callers must tolerate this and fall
  /// back to remote-only rendering, never crash).
  final String? localPath;

  /// The server's current best-guess remote counterpart for this slot, or
  /// `null` while the server does not yet have (this many) items of this
  /// [kind] at all.
  final String? remoteUrl;

  /// True only when [remoteUrl] (when non-null) was resolved via an EXACT
  /// `client_media_id` match against the server's own identity for that
  /// item -- never via the legacy order-based positional fallback (see
  /// the file-level doc comment's IDENTITY section). `false` whenever no
  /// remote match was found at all, OR the match came from the
  /// best-guess positional fallback.
  ///
  /// Real-device acceptance fix: callers (`car_details_page_media.dart`)
  /// use this to decide whether it is safe to still route display
  /// through the owner-fallback widget (and its `onRemoteDisplayReady`
  /// completion signal) for a slot whose own local-only row has already
  /// disappeared from the base merge (i.e. the server has since fully
  /// caught up) -- safe when the pairing is an EXACT, identity-based
  /// match (a genuinely-the-same-item guarantee), but NOT safe for a
  /// purely positional/legacy guess, where doing so could otherwise
  /// visibly mask an unrelated, already-correct server image behind a
  /// stale/orphaned local file from a completely different submission
  /// (see `listing_details_five_image_gallery_test.dart`'s "STALE
  /// pending record" regression test, which this flag exists to keep
  /// passing).
  final bool matchedById;

  bool get hasLocal => (localPath ?? '').trim().isNotEmpty;
  bool get hasRemote => (remoteUrl ?? '').trim().isNotEmpty;
}

/// Every expected media item for the owner's in-flight submission, plus
/// whether the durable local record backing it still exists at all
/// (`serverStillProcessing` -- the SAME signal
/// [OwnerPendingMediaMerge.isMediaProcessing] already uses: true from the
/// moment Submit is pressed until every expected item has been confirmed
/// attached server-side and the record is removed).
class OwnerMediaOverlayResult {
  const OwnerMediaOverlayResult({
    required this.slots,
    required this.serverStillProcessing,
  });

  static const empty = OwnerMediaOverlayResult(
    slots: <OwnerMediaSlot>[],
    serverStillProcessing: false,
  );

  final List<OwnerMediaSlot> slots;
  final bool serverStillProcessing;

  int get expectedCount => slots.length;

  List<OwnerMediaSlot> get imageSlots =>
      slots.where((s) => s.kind == OwnerMediaKind.image).toList();
  List<OwnerMediaSlot> get videoSlots =>
      slots.where((s) => s.kind == OwnerMediaKind.video).toList();

  bool get isEmpty => slots.isEmpty;
}

abstract final class OwnerMediaOverlay {
  OwnerMediaOverlay._();

  /// Reads the durable submission record for [car]'s id (if any -- and if
  /// [isOwner]) and builds per-slot local/remote pairs from it. Returns
  /// [OwnerMediaOverlayResult.empty] for a non-owner or an edit-mode
  /// record (see the file-level doc comment).
  ///
  /// Restart-safety fix (Critical Issue 1): a listing with no active
  /// [SellSubmissionRecord] is NO LONGER automatically empty -- the
  /// backend can have finished (clearing that record) while some/all
  /// remote items are still unconfirmed on THIS device (killed before a
  /// decode/initialization completed, or simply never opened Car Details
  /// during the submission). In that case, falls back to the durable
  /// [OwnerOptimisticMediaRecord] (`owner_optimistic_media_prefs.dart`),
  /// which outlives the submission record for exactly this reason. Only
  /// truly empty (nothing left to reconcile) once NEITHER record exists.
  ///
  /// Whichever source is used, also keeps the durable
  /// [OwnerOptimisticMediaRecord] itself up to date (fire-and-forget from
  /// the caller's perspective, but awaited here) -- this is what makes it
  /// exist at all the very first time a listing's media is examined, not
  /// only at backend-completion time (see
  /// `PendingSellSubmissionService.snapshotAtSubmissionCompleteAndMaybeFinalize`
  /// for the OTHER write site, which covers the case where Car Details is
  /// never opened while a submission is in flight).
  static Future<OwnerMediaOverlayResult> build({
    required Map<String, dynamic> car,
    required bool isOwner,
  }) async {
    if (!isOwner) return OwnerMediaOverlayResult.empty;
    final carId = listingPrimaryId(car);
    if (carId.isEmpty) return OwnerMediaOverlayResult.empty;
    final record = await OwnerPendingMediaMerge.recordForCarId(carId);
    if (record != null) {
      final result = buildFromRecord(car: car, record: record);
      if (!result.isEmpty) {
        await OwnerOptimisticMediaCleanup.syncFromItems(
          listingId: carId,
          freshItems: OwnerOptimisticMediaCleanup.itemsFromSlots(
            result.slots,
          ),
          draftId: record.draftId,
        );
      }
      return result;
    }
    return buildFromOptimisticRecordForCarId(car: car, carId: carId);
  }

  /// Real-device acceptance fix ("My Listings card shows zero photos
  /// until I open Car Details"): [OwnerPendingMediaMerge.mergeIfOwner]/
  /// [mergeOwnedListings] only ever read the LIVE [SellSubmissionRecord]
  /// -- which `PendingSellSubmissionService._runSubmission`'s success
  /// path removes the INSTANT the backend finishes, typically well
  /// before the owner ever leaves the Sell flow (i.e. before My Listings
  /// even has a chance to render the new card once). From that moment
  /// on, those two methods are permanent no-ops for this listing, even
  /// though the exact same durable [OwnerOptimisticMediaRecord] fallback
  /// Car Details already relies on (via [build]) is still sitting there
  /// with every expected item's local path. This produces a simplified
  /// `images`/`videos` list for CARD-style surfaces (My Listings, or any
  /// future owner-facing card grid) using that SAME slot pipeline, so a
  /// brand-new listing's card shows its just-picked photos/videos
  /// immediately regardless of whether the live record still exists.
  ///
  /// Appends one local-fallback entry per slot that does not yet have a
  /// remote counterpart; never removes/reorders any existing
  /// server-confirmed entry (same "only ever ADD past what the server
  /// already has" guarantee as `OwnerPendingMediaMerge._merge`). Returns
  /// [car] unchanged (same instance) when there is nothing to add.
  static Future<Map<String, dynamic>> mergeForCardDisplay(
    Map<String, dynamic> car, {
    required bool isOwner,
  }) async {
    if (!isOwner) return car;
    final result = await build(car: car, isOwner: isOwner);
    return _appendLocalFallbackForCardDisplay(car, result);
  }

  static Map<String, dynamic> _appendLocalFallbackForCardDisplay(
    Map<String, dynamic> car,
    OwnerMediaOverlayResult result,
  ) {
    if (result.isEmpty) return car;
    final localImages = <dynamic>[];
    final localVideos = <dynamic>[];
    for (final slot in result.slots) {
      // Only a slot with genuinely nothing server-side yet (never a
      // slot the server already has, matched or not) -- identical
      // "remoteUrl == null" safety gate as the Car Details stable-slots
      // fix (`car_details_page_media.dart`'s `_applyOwnerImageFallbackOverlay`),
      // so a card never shows a stale local file once the server side is
      // already accounted for.
      if (!slot.hasLocal || slot.hasRemote) continue;
      if (slot.kind == OwnerMediaKind.image) {
        localImages.add(slot.localPath);
      } else {
        localVideos.add(slot.localPath);
      }
    }
    if (localImages.isEmpty && localVideos.isEmpty) return car;
    final merged = Map<String, dynamic>.from(car);
    if (localImages.isNotEmpty) {
      final existing = (merged['images'] is List)
          ? List<dynamic>.from(merged['images'] as List)
          : <dynamic>[];
      merged['images'] = [...existing, ...localImages];
    }
    if (localVideos.isNotEmpty) {
      final existing = (merged['videos'] is List)
          ? List<dynamic>.from(merged['videos'] as List)
          : <dynamic>[];
      merged['videos'] = [...existing, ...localVideos];
    }
    return merged;
  }

  /// Bulk variant of [mergeForCardDisplay] for a whole listing page (e.g.
  /// My Listings) -- same efficiency shape as
  /// [OwnerPendingMediaMerge.mergeOwnedListings]: reads the durable
  /// [OwnerOptimisticMediaPrefs] list ONCE for the whole batch (never once
  /// per card), and only does the (pure, no-IO) per-slot pairing work for
  /// a listing that actually still has an unfinished durable record.
  /// Every listing in [cars] is assumed to already be owned by the
  /// current account (true for e.g. `GET /api/my-listings` results) --
  /// callers that mix owned and non-owned listings must use
  /// [mergeForCardDisplay] per-item instead.
  static Future<List<Map<String, dynamic>>> mergeOwnedListingsForCardDisplay(
    List<Map<String, dynamic>> cars,
  ) async {
    // Step 1: the existing, cheap live-record merge (unchanged) -- still
    // the right source whenever a submission's backend call has not
    // finished yet.
    final liveMerged = await OwnerPendingMediaMerge.mergeOwnedListings(cars);
    // Step 2: durable-record fallback for whatever still has local media
    // not yet confirmed remote-display-ready on this device -- the
    // common case once backend-done has already removed the live record
    // (see this method's own file-level doc comment above).
    final optimisticRecords = await OwnerOptimisticMediaPrefs.loadAll();
    if (optimisticRecords.isEmpty) return liveMerged;
    final byListingId = <String, OwnerOptimisticMediaRecord>{
      for (final r in optimisticRecords) r.listingId: r,
    };
    if (byListingId.isEmpty) return liveMerged;
    final out = <Map<String, dynamic>>[];
    for (final car in liveMerged) {
      final carId = listingPrimaryId(car);
      final record = carId.isEmpty ? null : byListingId[carId];
      if (record == null || record.isEmpty || record.allRemoteDisplayReady) {
        out.add(car);
        continue;
      }
      final result = buildFromOptimisticRecord(car: car, record: record);
      out.add(_appendLocalFallbackForCardDisplay(car, result));
    }
    return out;
  }

  /// The restart-safe fallback path -- see [build]'s doc comment. Public
  /// (not just reached through [build]) so tests can exercise it directly
  /// against a hand-built persisted record, exactly like [buildFromRecord].
  static Future<OwnerMediaOverlayResult> buildFromOptimisticRecordForCarId({
    required Map<String, dynamic> car,
    required String carId,
  }) async {
    final persisted = await OwnerOptimisticMediaPrefs.load(carId);
    if (persisted == null || persisted.isEmpty) {
      return OwnerMediaOverlayResult.empty;
    }
    return buildFromOptimisticRecord(car: car, record: persisted);
  }

  /// Pure (no disk I/O) variant of [buildFromOptimisticRecordForCarId] --
  /// exposed for tests, mirroring [buildFromRecord].
  ///
  /// Real-device acceptance fix: this used to do EXACT `client_media_id`
  /// matching ONLY (`imageById[item.clientMediaId]` /
  /// `videoById[item.clientMediaId]`), with no fallback at all -- unlike
  /// [buildFromRecord], which already has a documented legacy
  /// positional-within-kind fallback for remote rows that carry no id
  /// (see that method's own comments). Since [buildFromOptimisticRecord]
  /// is the path used for EVERY listing once its `SellSubmissionRecord`
  /// is gone (i.e. shortly after any successful submission -- see
  /// [build]'s doc comment), missing this fallback meant ANY listing
  /// whose backend response doesn't carry `client_media_id` on a given
  /// item (either because that owner-only field genuinely isn't deployed
  /// yet, or because the row predates it) would show that item as
  /// permanently local-only -- confirmed on a real device: 5 correctly
  /// server-attached images stayed `remote_url=null` forever because the
  /// live backend didn't yet return `client_media_id` for them.
  ///
  /// Same matching order/guarantees as [buildFromRecord]'s image/video
  /// loops, applied per [OwnerMediaKind] independently (an image can
  /// never consume a video's remote URL or vice versa, mirroring
  /// [_remoteImageSources]/[_remoteVideoSources] already being kept
  /// separate):
  /// 1. Exact `client_media_id` match always wins when the server has
  ///    one for this local item.
  /// 2. Only when the server has genuinely id-less remote rows LEFT does
  ///    a not-yet-matched local item fall back to the next one in
  ///    encounter order (one remote row is never consumed twice: each
  ///    row is removed from its kind's legacy pool the moment it is
  ///    used).
  /// 3. [record.items] is iterated in its own stored (original expected)
  ///    order, so output order always matches input order regardless of
  ///    which branch resolved each slot's `remoteUrl`.
  static OwnerMediaOverlayResult buildFromOptimisticRecord({
    required Map<String, dynamic> car,
    required OwnerOptimisticMediaRecord record,
  }) {
    if (record.isEmpty) return OwnerMediaOverlayResult.empty;
    final remoteImages = _remoteImageSources(car);
    final remoteVideos = _remoteVideoSources(car);
    final imageById = <String, String>{};
    final imageLegacyPool = <String>[];
    for (final e in remoteImages) {
      final cmid = e.clientMediaId;
      if (cmid != null && cmid.isNotEmpty) {
        imageById[cmid] = e.url;
      } else {
        imageLegacyPool.add(e.url);
      }
    }
    final videoById = <String, String>{};
    final videoLegacyPool = <String>[];
    for (final e in remoteVideos) {
      final cmid = e.clientMediaId;
      if (cmid != null && cmid.isNotEmpty) {
        videoById[cmid] = e.url;
      } else {
        videoLegacyPool.add(e.url);
      }
    }
    var imageLegacyIdx = 0;
    var videoLegacyIdx = 0;
    final slots = record.items.map((item) {
      final isImage = item.kind == 'image';
      // Exact match first -- never overridden by positional fallback even
      // if it happens to resolve to the same pool position.
      var refreshedRemote = isImage
          ? imageById[item.clientMediaId]
          : videoById[item.clientMediaId];
      final exactMatch = refreshedRemote != null;
      if (refreshedRemote == null) {
        // Only fall back to the next unconsumed legacy (id-less) remote
        // row of the SAME kind -- never across kinds, never re-consuming
        // a row another slot already claimed.
        if (isImage && imageLegacyIdx < imageLegacyPool.length) {
          refreshedRemote = imageLegacyPool[imageLegacyIdx];
          imageLegacyIdx++;
        } else if (!isImage && videoLegacyIdx < videoLegacyPool.length) {
          refreshedRemote = videoLegacyPool[videoLegacyIdx];
          videoLegacyIdx++;
        }
      }
      return OwnerMediaSlot(
        clientMediaId: item.clientMediaId,
        kind: isImage ? OwnerMediaKind.image : OwnerMediaKind.video,
        order: item.order,
        localPath: item.remoteDisplayReady ? null : item.localPath,
        remoteUrl: refreshedRemote ?? item.remoteUrl,
        // Only a FRESH exact `client_media_id` match this call counts --
        // never the legacy positional-pool fallback, and never the
        // persisted `item.remoteUrl` carried over from a previous run
        // (that value could itself have originally come from a
        // positional guess; not re-verified here).
        matchedById: exactMatch,
      );
    }).toList();
    return OwnerMediaOverlayResult(
      slots: slots,
      // The persisted record's mere existence already means "not every
      // expected item is remote-display-ready yet" -- see
      // `OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup`,
      // which removes the record the instant that stops being true.
      serverStillProcessing: true,
    );
  }

  /// Pure (no disk I/O) slot-building from an already-loaded [record] --
  /// exposed separately so tests can exercise the reconciliation logic
  /// directly against hand-built records/car maps, exactly like
  /// `owner_pending_media_merge_test.dart` does for [OwnerPendingMediaMerge].
  /// Enforces the edit-mode scope guard itself (not just in [build]) so
  /// this is safe to call directly without relying on the caller to have
  /// already checked [SellSubmissionRecord.isEdit] -- see the file-level
  /// doc comment for why edit-mode is out of scope.
  static OwnerMediaOverlayResult buildFromRecord({
    required Map<String, dynamic> car,
    required SellSubmissionRecord record,
  }) {
    if (record.isEdit) return OwnerMediaOverlayResult.empty;
    final slots = <OwnerMediaSlot>[];

    // ---- Listing (non-damage) images ----
    // `finalListingImages` is the SAME authoritative source
    // `SellMediaIdentity.buildExpectedMedia`/the real Phase-A upload use --
    // never a stale `blurred_images` preview list (see its own doc
    // comment). For a fresh (non-edit) submission this is entirely local
    // items, in the exact order they were uploaded/enqueued.
    final localImages = SellMediaIdentity.finalListingImages(record.carData);
    final remoteImages = _remoteImageSources(car);
    final imageById = <String, String>{};
    final imageLegacyPool = <String>[];
    for (final e in remoteImages) {
      final cmid = e.clientMediaId;
      if (cmid != null && cmid.isNotEmpty) {
        imageById[cmid] = e.url;
      } else {
        imageLegacyPool.add(e.url);
      }
    }
    var imageOrder = 0;
    var imageLegacyIdx = 0;
    for (final item in localImages) {
      final id = SellMediaIdentity.forImageItem(item, kind: 'listing');
      // `null` means this entry is already a server-attached image (has a
      // numeric id) -- not part of Phase A, nothing to reconcile.
      if (id == null) continue;
      final idx = imageOrder;
      // Exact match first (see the file-level doc comment); only fall
      // back to positional-within-legacy-pool pairing when the server
      // has genuinely id-less remote images left to pair against --
      // never against an id'd remote image that simply belongs to a
      // DIFFERENT, not-yet-matched local item.
      var remoteUrl = imageById[id];
      final exactMatch = remoteUrl != null;
      if (remoteUrl == null && imageLegacyIdx < imageLegacyPool.length) {
        remoteUrl = imageLegacyPool[imageLegacyIdx];
        imageLegacyIdx++;
      }
      slots.add(
        OwnerMediaSlot(
          clientMediaId: id,
          kind: OwnerMediaKind.image,
          order: idx,
          // Real-device acceptance fix (HEIC "Could not decompress image" /
          // hero-image retry state surfacing for a newly-inserted
          // stable-slots fallback -- see `car_details_page_media.dart`):
          // prefer the HEIC/HEIF local preview JPEG
          // (`ListingImageMedia.previewLocalFile`) over the raw original
          // (`localFile`) for RENDERING purposes -- Skia cannot decode a
          // `.heif`/`.heic` file directly on most Android versions, so a
          // slot whose only available source is the untouched original
          // would otherwise render as a broken image (and trip
          // `ListingHeroImage`'s retry/error state) for every second it
          // takes the background HEIC-preview conversion to finish, or
          // forever if that slot is never also tagged onto an existing
          // plain entry. `previewLocalFile` already falls back to
          // `localFile` itself for JPEG/PNG originals or a HEIC whose
          // conversion hasn't finished/failed yet, so this is strictly
          // additive -- never worse than before for any non-HEIC item.
          localPath: ListingImageMedia.previewLocalFile(item)?.path,
          remoteUrl: remoteUrl,
          matchedById: exactMatch,
        ),
      );
      imageOrder++;
    }

    // ---- Normal (non-server-transcode) videos: exact `client_media_id`
    // match first, legacy positional-within-kind fallback otherwise, same
    // reasoning as images. Server-transcode-attached `CarVideo` rows
    // (below) now ALSO carry their own `client_media_id` (the same
    // `draftMediaId` their local spec already tracks), so they never
    // land in `videoLegacyPool` and are never mistaken for a normal
    // video's remote counterpart -- replaces the old, more fragile
    // `remoteNormalCount` count-subtraction. ----
    final localVideos = (record.carData['videos'] is List)
        ? List<dynamic>.from(record.carData['videos'] as List)
        : const <dynamic>[];
    final remoteVideos = _remoteVideoSources(car);
    final videoById = <String, String>{};
    final videoLegacyPool = <String>[];
    for (final e in remoteVideos) {
      final cmid = e.clientMediaId;
      if (cmid != null && cmid.isNotEmpty) {
        videoById[cmid] = e.url;
      } else {
        videoLegacyPool.add(e.url);
      }
    }
    final transcodeSpecs = ServerTranscodeVideoSpec.listFromJson(
      record.carData['server_transcode_videos'],
    );

    var videoOrder = 0;
    var videoLegacyIdx = 0;
    for (final item in localVideos) {
      final id = SellMediaIdentity.forNormalVideoItem(item);
      if (id == null) continue;
      final idx = videoOrder;
      var remoteUrl = videoById[id];
      final exactMatch = remoteUrl != null;
      if (remoteUrl == null && videoLegacyIdx < videoLegacyPool.length) {
        remoteUrl = videoLegacyPool[videoLegacyIdx];
        videoLegacyIdx++;
      }
      slots.add(
        OwnerMediaSlot(
          clientMediaId: id,
          kind: OwnerMediaKind.video,
          order: idx,
          localPath: ListingImageMedia.localFile(item)?.path ??
              (item is String ? item : null),
          remoteUrl: remoteUrl,
          matchedById: exactMatch,
        ),
      );
      videoOrder++;
    }

    // ---- Server-transcode videos: EXACT client_media_id (draft_media_id)
    // match -- this client durably tracks each one's own terminal
    // `attachedVideo` dict keyed by draftMediaId (see
    // `sell_server_transcode_video.dart`), so no positional guessing is
    // needed here at all. ----
    for (final spec in transcodeSpecs) {
      final state = record.serverTranscodeVideos[spec.draftMediaId];
      final attached = state?.status == ServerTranscodeVideoStatus.attached;
      final remoteUrl =
          attached ? _videoUrlFromAttached(state!.attachedVideo) : null;
      slots.add(
        OwnerMediaSlot(
          clientMediaId: spec.draftMediaId,
          kind: OwnerMediaKind.video,
          order: videoOrder,
          localPath: spec.localSourcePath,
          remoteUrl: remoteUrl,
          // Always identity-based (keyed by `draftMediaId`) -- never a
          // positional guess, see the comment above this loop.
          matchedById: remoteUrl != null,
        ),
      );
      videoOrder++;
    }

    return OwnerMediaOverlayResult(
      slots: slots,
      // Mirrors `OwnerPendingMediaMerge.isMediaProcessing`'s exact
      // semantics: a durable record for this carId existing on THIS
      // device already means the background media pipeline has not yet
      // confirmed every expected item attached (the record is removed the
      // instant it has -- see `PendingSellSubmissionService._runSubmission`'s
      // success path). The backend's own `Car.media_status` column is not
      // otherwise exposed on the regular `GET /api/cars/<id>` response
      // consumed here (only via the separate `/media-summary` endpoint),
      // so this local signal is condition "A" from the owner-optimistic-
      // display badge contract; condition "B" (expected vs.
      // remote-display-ready count) is computed by the caller from
      // [slots] plus its own live per-tile load-success tracking -- see
      // `car_details_page_media.dart`.
      serverStillProcessing: true,
    );
  }

  /// [PendingSellSubmissionService]'s own completion-time snapshot source
  /// (see `owner_optimistic_media_cleanup.dart`'s
  /// `snapshotAtSubmissionCompleteAndMaybeFinalize`): the same identity/
  /// local-path resolution [buildFromRecord] does, but with no live `car`
  /// response available at that call site (nothing has necessarily been
  /// re-fetched from the server there) -- so every slot's `remoteUrl`
  /// comes back `null` here. That is fine: this snapshot's only job is to
  /// guarantee the durable record exists (so it survives a kill even if
  /// Car Details is never opened); the real remote URLs get filled in the
  /// next time [build] runs against a live `car` response.
  static List<OwnerOptimisticMediaItem> snapshotItemsFromRecord(
    SellSubmissionRecord record,
  ) {
    final result = buildFromRecord(
      car: const <String, dynamic>{},
      record: record,
    );
    return OwnerOptimisticMediaCleanup.itemsFromSlots(result.slots);
  }

  static List<_RemoteMediaEntry> _remoteImageSources(
    Map<String, dynamic> car,
  ) {
    final imgs = (car['images'] is List)
        ? List<dynamic>.from(car['images'] as List)
        : const <dynamic>[];
    final out = <_RemoteMediaEntry>[];
    for (final it in imgs) {
      final kind = (it is Map ? (it['kind'] ?? 'listing') : 'listing')
          .toString()
          .toLowerCase();
      if (kind == 'damage') continue;
      final s = ListingImageMedia.source(it);
      if (s.isEmpty) continue;
      final cmid = it is Map
          ? (it['client_media_id']?.toString().trim())
          : null;
      out.add((clientMediaId: (cmid?.isEmpty ?? true) ? null : cmid, url: s));
    }
    return out;
  }

  static List<_RemoteMediaEntry> _remoteVideoSources(
    Map<String, dynamic> car,
  ) {
    final vids = (car['videos'] is List)
        ? List<dynamic>.from(car['videos'] as List)
        : const <dynamic>[];
    final out = <_RemoteMediaEntry>[];
    for (final it in vids) {
      final s = it is Map
          ? (it['video_url'] ?? it['url'] ?? it['path'] ?? it['source'] ?? '')
              .toString()
              .trim()
          : it.toString().trim();
      if (s.isEmpty || s == 'null') continue;
      final cmid = it is Map
          ? (it['client_media_id']?.toString().trim())
          : null;
      out.add((clientMediaId: (cmid?.isEmpty ?? true) ? null : cmid, url: s));
    }
    return out;
  }

  static String? _videoUrlFromAttached(Map<String, dynamic>? attachedVideo) {
    if (attachedVideo == null) return null;
    final s = (attachedVideo['video_url'] ??
            attachedVideo['url'] ??
            attachedVideo['path'] ??
            '')
        .toString()
        .trim();
    return s.isEmpty ? null : s;
  }
}
