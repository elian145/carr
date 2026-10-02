part of 'car_details_page.dart';

/// Test-only interception point for
/// `_CarDetailsPageMedia._backgroundProbeImageDecodes` -- same
/// contract/rationale as `debugOwnerFallbackHeroRemoteProbeOverride`
/// (`owner_fallback_hero_image.dart`), just declared here (rather than
/// reusing that widget's own hook directly) so setting it from this
/// page's background prober never trips
/// `invalid_use_of_visible_for_testing_member` (this page's library is
/// not `OwnerFallbackHeroImage`'s declaring library). Always `null` in
/// production; tests MUST reset to `null` in `tearDown`.
@visibleForTesting
Future<bool> Function(String url)?
    debugCarDetailsBackgroundImageProbeOverride;

/// Video-kind counterpart of
/// [debugCarDetailsBackgroundImageProbeOverride] -- mirrors
/// `debugOwnerFallbackVideoRemoteProbeOverride`
/// (`owner_fallback_video_thumbnail.dart`) for the same reason.
@visibleForTesting
Future<Uint8List?> Function(String url)?
    debugCarDetailsBackgroundVideoProbeOverride;

mixin _CarDetailsPageMedia on _CarDetailsPageOwner {
  /// Optimistic-submission fix (task item #14): true for a raw media
  /// reference that is a local device file (from this device's own
  /// still-in-flight Sell submission -- see `owner_pending_media_merge
  /// .dart`), as opposed to a genuine server URL/relative path. Local
  /// references must never be passed through [buildLegacyFullImageUrl]
  /// (which assumes every input is server-relative and would mangle an
  /// absolute device path into a broken URL) -- they are used AS-IS, since
  /// every renderer that ends up consuming them
  /// (`listingCachedNetworkImageProvider` / `listingNetworkImage` /
  /// `NetworkVideoThumbnailPreview` / `GalleryEmbeddedVideoPlayer`)
  /// already auto-detects and renders a local path directly.
  bool _isLocalMediaPath(String raw) => ListingImageMedia.localFile(raw) != null;

  String _resolveHeroMediaUrl(String raw) =>
      _isLocalMediaPath(raw) ? raw : buildLegacyFullImageUrl(raw);

  List<String> get _imageUrls {
    return _heroImageEntries.map((e) => e.url).toList(growable: false);
  }

  /// Listing (non-damage) images with optional car-detection metadata for
  /// hero crop, plus (optimistic-local-media fix) the owner-overlay
  /// local/remote fallback pair for this entry when applicable --
  /// `ownerFallbackClientMediaId` non-null tells
  /// `car_details_page_build_hero.dart` to render an
  /// `OwnerFallbackHeroImage` for this entry instead of a plain
  /// `ListingHeroImage(url: entry.url)`, using `ownerFallbackLocalUrl`/
  /// `ownerFallbackRemoteUrl` as its two candidate sources. `null` for
  /// every entry when there is no active owner overlay for this listing
  /// (non-owner, edit-mode, or media pipeline already finished) --
  /// behaviorally identical to before this fix in that case.
  List<
      ({
        String url,
        Map<String, dynamic>? meta,
        String? ownerFallbackLocalUrl,
        String? ownerFallbackRemoteUrl,
        String? ownerFallbackClientMediaId,
      })> get _heroImageEntries {
    final List<({String url, Map<String, dynamic>? meta})> entries = [];
    if (car == null) return const [];

    final List<dynamic> imgs =
        (car!['images'] is List) ? (car!['images'] as List) : const [];

    void addUrl(String raw, Map<String, dynamic>? meta) {
      if (raw.isEmpty) return;
      final full = _resolveHeroMediaUrl(raw);
      if (full.isEmpty) return;
      if (entries.any((e) => e.url == full)) return;
      entries.add((url: full, meta: meta));
    }

    Map<String, dynamic>? metaFrom(dynamic it) {
      if (it is! Map) return null;
      return Map<String, dynamic>.from(it);
    }

    bool isDamage(dynamic it) =>
        it is Map &&
        (it['kind'] ?? '').toString().toLowerCase() == 'damage';

    final String primary = (car!['image_url'] ?? '').toString();
    if (primary.isNotEmpty) {
      Map<String, dynamic>? primaryMeta;
      for (final dynamic it in imgs) {
        if (isDamage(it)) continue;
        final s = ListingImageMedia.source(it);
        if (s.isNotEmpty &&
            (buildLegacyFullImageUrl(s) == buildLegacyFullImageUrl(primary) ||
                s == primary)) {
          primaryMeta = metaFrom(it);
          break;
        }
      }
      // Listing-level detection metadata (rare) as fallback for primary.
      primaryMeta ??= () {
        final det = car!['car_detection'] ??
            car!['primary_car_bbox'] ??
            car!['hero_detection'];
        if (det == null) return null;
        return <String, dynamic>{'car_detection': det};
      }();
      addUrl(primary, primaryMeta);
    }

    for (final dynamic it in imgs) {
      if (isDamage(it)) continue;
      final s = ListingImageMedia.source(it);
      addUrl(s, metaFrom(it));
    }

    // If no explicit primary but images exist, first listing image is hero.
    if (entries.isEmpty && imgs.isNotEmpty) {
      for (final dynamic it in imgs) {
        if (isDamage(it)) continue;
        final s = ListingImageMedia.source(it);
        if (s.isNotEmpty) {
          addUrl(s, metaFrom(it));
          break;
        }
      }
    }

    return _applyOwnerImageFallbackOverlay(entries);
  }

  /// (optimistic-local-media fix) Post-processes the plain
  /// url/meta [entries] built above -- unchanged for everyone except an
  /// owner viewing their own listing while its Phase-A media pipeline is
  /// still active (see `owner_media_overlay.dart`). For each expected
  /// image slot: tags the entry that corresponds to its LOCAL file with
  /// the fallback fields (so the hero-build site renders
  /// `OwnerFallbackHeroImage` for it), and -- if the slot's REMOTE url has
  /// ALSO already landed as its own separate entry in [entries] (the
  /// pre-existing `OwnerPendingMediaMerge` merge appends local fallbacks
  /// unconditionally alongside whatever the server already has, by
  /// design -- see that file's own doc comment) -- removes that separate
  /// remote entry, so the same photo is never shown twice while the
  /// fallback widget itself is responsible for the local->remote swap.
  ///
  /// Real-device acceptance fix (stuck-at-0/N "Processing media" badge):
  /// `OwnerPendingMediaMerge` ONLY appends a slot's local file as a
  /// separate entry while the server has NOT yet attached that item --
  /// once every expected item has landed server-side (the common case by
  /// the time an owner actually looks, since Phase-A processing is
  /// usually fast), [entries] contains ONLY the remote URLs, with no
  /// local-only row left to match against `slot.localPath` at all. The
  /// OLD logic required finding that local-only row first and gave up
  /// entirely if it was already gone -- silently falling through to a
  /// plain `ListingHeroImage(url: remoteUrl)` for every slot, which never
  /// calls `onRemoteDisplayReady`, so `remote_display_ready` could never
  /// reach `expected` and the badge never cleared, even though the
  /// photo/video was already displaying correctly. Now: if no local-only
  /// row exists, fall back to tagging the slot's REMOTE entry instead (it
  /// is always present whenever `slot.hasRemote` is true) with the same
  /// fallback fields -- `OwnerFallbackHeroImage` still renders
  /// `ownerFallbackLocalUrl` first and only flips to remote (firing
  /// `onRemoteDisplayReady`) once its own probe confirms the remote image
  /// genuinely decodes, exactly as when a separate local-only row exists.
  List<
      ({
        String url,
        Map<String, dynamic>? meta,
        String? ownerFallbackLocalUrl,
        String? ownerFallbackRemoteUrl,
        String? ownerFallbackClientMediaId,
      })> _applyOwnerImageFallbackOverlay(
    List<({String url, Map<String, dynamic>? meta})> entries,
  ) {
    final overlay = _ownerMediaOverlay;
    final out = entries
        .map<
            ({
              String url,
              Map<String, dynamic>? meta,
              String? ownerFallbackLocalUrl,
              String? ownerFallbackRemoteUrl,
              String? ownerFallbackClientMediaId,
            })>(
          (e) => (
            url: e.url,
            meta: e.meta,
            ownerFallbackLocalUrl: null,
            ownerFallbackRemoteUrl: null,
            ownerFallbackClientMediaId: null,
          ),
        )
        .toList();
    if (overlay == null || overlay.imageSlots.isEmpty) return out;

    final removeIndices = <int>{};
    for (final slot in overlay.imageSlots) {
      final localUrl = (slot.localPath ?? '').trim().isEmpty
          ? null
          : _resolveHeroMediaUrl(slot.localPath!);
      final remoteUrl = slot.hasRemote
          ? _resolveHeroMediaUrl(slot.remoteUrl!)
          : null;
      if (localUrl == null) {
        // No local preview path at all for this slot -- nothing to tag
        // and nothing to insert; fall through so a plain server entry
        // (if any) is left exactly as-is.
        continue;
      }
      final localIdx = out.indexWhere((e) => e.url == localUrl);
      if (localIdx != -1) {
        out[localIdx] = (
          url: out[localIdx].url,
          meta: out[localIdx].meta,
          ownerFallbackLocalUrl: localUrl,
          ownerFallbackRemoteUrl: remoteUrl,
          ownerFallbackClientMediaId: slot.clientMediaId,
        );
        if (remoteUrl != null) {
          final remoteIdx = out.indexWhere((e) => e.url == remoteUrl);
          if (remoteIdx != -1 && remoteIdx != localIdx) {
            removeIndices.add(remoteIdx);
          }
        }
        continue;
      }
      // No separate local-only row left (server already fully caught up
      // for this slot, OR this slot's legacy-positional pairing simply
      // reused one of the server's existing rows -- see below). If the
      // overlay found ANY remote url for this slot at all, that url
      // originated from `car!['images']` itself (see
      // `OwnerMediaOverlay._remoteImageSources`), so it is either
      // already present in [entries] as its own plain row (the common
      // case) or was filtered out upstream for an unrelated reason --
      // either way, a non-null `remoteUrl` means the server side of this
      // ordinal slot is already accounted for and nothing must be
      // inserted, to avoid ever showing a duplicate/stale local file
      // alongside it (see `listing_details_five_image_gallery_test.dart`'s
      // "STALE pending record" regression test). Only an EXACT
      // `client_media_id` match (`slot.matchedById`) is safe enough to
      // also TAG that existing row with the fallback fields (so it still
      // routes through `onRemoteDisplayReady`); a purely positional/
      // legacy guess is left as a plain, already-correct server entry.
      if (remoteUrl != null) {
        if (slot.matchedById) {
          final remoteOnlyIdx = out.indexWhere((e) => e.url == remoteUrl);
          if (remoteOnlyIdx != -1) {
            out[remoteOnlyIdx] = (
              url: out[remoteOnlyIdx].url,
              meta: out[remoteOnlyIdx].meta,
              ownerFallbackLocalUrl: localUrl,
              ownerFallbackRemoteUrl: remoteUrl,
              ownerFallbackClientMediaId: slot.clientMediaId,
            );
          }
        }
        continue;
      }
      // Stable-slots fix: `remoteUrl == null` here means the server
      // genuinely has NOTHING yet for this ordinal slot of this kind
      // (not even a legacy/positional guess) -- e.g. right after listing
      // creation, before any media has attached server-side at all.
      // Without this branch the slot would be silently missing from the
      // gallery entirely, which is exactly the "1/6, 3/6, ... growing"
      // bug the stable-slot-count requirement exists to fix. Insert a
      // brand-new entry using the local preview as its initial source,
      // so every genuinely-not-yet-attached expected item always has
      // exactly one slot from the very first frame.
      out.add((
        url: localUrl,
        meta: null,
        ownerFallbackLocalUrl: localUrl,
        ownerFallbackRemoteUrl: remoteUrl,
        ownerFallbackClientMediaId: slot.clientMediaId,
      ));
    }
    if (removeIndices.isEmpty) return out;
    return [
      for (var i = 0; i < out.length; i++)
        if (!removeIndices.contains(i)) out[i],
    ];
  }

  /// Normalizes API `videos` (strings and/or `{video_url: ...}` maps) to relative paths.
  static List<String> _normalizeVideoPaths(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    final List<String> out = [];
    for (final dynamic it in raw) {
      String s = '';
      if (it is String) {
        s = it.trim();
      } else if (it is Map) {
        final map = Map<String, dynamic>.from(it);
        s = (map['video_url'] ?? map['url'] ?? map['path'] ?? map['source'] ?? '')
            .toString()
            .trim();
      } else {
        s = it.toString().trim();
      }
      if (s.isNotEmpty && !s.startsWith('{') && s != 'null') {
        out.add(s);
      }
    }
    return out;
  }

  Map<String, dynamic> _normalizeCarDetailMap(Map<String, dynamic> src) {
    final m = Map<String, dynamic>.from(src);
    m['videos'] = _normalizeVideoPaths(m['videos']);
    return m;
  }

  List<String> get _videoUrls =>
      _heroVideoEntries.map((e) => e.url).toList(growable: false);

  /// (optimistic-local-media fix) Video counterpart of [_heroImageEntries]
  /// -- same owner-overlay tagging/dedupe-of-the-now-separately-landed-
  /// remote-entry logic, just for `car!['videos']` instead of
  /// `car!['images']`. `_videoUrls` (used by [_heroMediaCount] and the
  /// full-screen gallery) derives from this so every consumer of the
  /// video list sees the SAME (deduped) count.
  List<
      ({
        String url,
        String? ownerFallbackLocalUrl,
        String? ownerFallbackRemoteUrl,
        String? ownerFallbackClientMediaId,
      })> get _heroVideoEntries {
    final List<String> plainUrls = [];
    if (car != null) {
      final paths = _normalizeVideoPaths(car!['videos']);
      for (final String s in paths) {
        final full = _resolveHeroMediaUrl(s);
        if (full.isNotEmpty && !plainUrls.contains(full)) plainUrls.add(full);
      }
    }
    final out = plainUrls
        .map<
            ({
              String url,
              String? ownerFallbackLocalUrl,
              String? ownerFallbackRemoteUrl,
              String? ownerFallbackClientMediaId,
            })>(
          (u) => (
            url: u,
            ownerFallbackLocalUrl: null,
            ownerFallbackRemoteUrl: null,
            ownerFallbackClientMediaId: null,
          ),
        )
        .toList();

    final overlay = _ownerMediaOverlay;
    if (overlay == null || overlay.videoSlots.isEmpty) return out;

    final removeIndices = <int>{};
    for (final slot in overlay.videoSlots) {
      final localUrl = (slot.localPath ?? '').trim().isEmpty
          ? null
          : _resolveHeroMediaUrl(slot.localPath!);
      final remoteUrl =
          slot.hasRemote ? _resolveHeroMediaUrl(slot.remoteUrl!) : null;
      if (localUrl == null) continue;
      final localIdx = out.indexWhere((e) => e.url == localUrl);
      if (localIdx != -1) {
        out[localIdx] = (
          url: out[localIdx].url,
          ownerFallbackLocalUrl: localUrl,
          ownerFallbackRemoteUrl: remoteUrl,
          ownerFallbackClientMediaId: slot.clientMediaId,
        );
        if (remoteUrl != null) {
          final remoteIdx = out.indexWhere((e) => e.url == remoteUrl);
          if (remoteIdx != -1 && remoteIdx != localIdx) {
            removeIndices.add(remoteIdx);
          }
        }
        continue;
      }
      // Real-device acceptance fix / stable-slots fix (see
      // `_applyOwnerImageFallbackOverlay`'s matching doc comment for the
      // full reasoning): a non-null `remoteUrl` means the server side of
      // this ordinal video slot is already accounted for somewhere in
      // [entries] (or was deliberately filtered) -- never insert a
      // duplicate/stale local fallback alongside it. Only tag that
      // existing row when the pairing is an EXACT `client_media_id`
      // match; a merely positional/legacy guess is left as a plain,
      // already-correct server entry.
      if (remoteUrl != null) {
        if (slot.matchedById) {
          final remoteOnlyIdx = out.indexWhere((e) => e.url == remoteUrl);
          if (remoteOnlyIdx != -1) {
            out[remoteOnlyIdx] = (
              url: out[remoteOnlyIdx].url,
              ownerFallbackLocalUrl: localUrl,
              ownerFallbackRemoteUrl: remoteUrl,
              ownerFallbackClientMediaId: slot.clientMediaId,
            );
          }
        }
        continue;
      }
      // `remoteUrl == null`: the server genuinely has nothing yet for
      // this ordinal video slot -- insert one now using the local
      // preview so the video's slot still appears immediately instead of
      // being silently missing until the server catches up, and so it
      // never gets appended again as an extra ("seventh") item once the
      // remote URL does land.
      out.add((
        url: localUrl,
        ownerFallbackLocalUrl: localUrl,
        ownerFallbackRemoteUrl: remoteUrl,
        ownerFallbackClientMediaId: slot.clientMediaId,
      ));
    }
    if (removeIndices.isEmpty) return out;
    return [
      for (var i = 0; i < out.length; i++)
        if (!removeIndices.contains(i)) out[i],
    ];
  }

  int get _heroMediaCount => _imageUrls.length + _videoUrls.length;

  /// (optimistic-local-media fix) Fires exactly once per distinct remote
  /// URL that a fallback widget confirms has genuinely finished
  /// loading/rendering -- see `owner_fallback_hero_image.dart`/
  /// `owner_fallback_video_thumbnail.dart`. Drives the "Processing media"
  /// badge completion rule (condition B) alongside the durable-record
  /// signal (condition A) -- see `_showProcessingMedia`.
  void _markOwnerMediaRemoteDisplayReady(String clientMediaId) {
    if (_remoteDisplayReady[clientMediaId] == true) return;
    if (!mounted) return;
    setState(() => _remoteDisplayReady[clientMediaId] = true);
    // Optimistic-local-media fix (Critical Issue 1): this in-memory flag
    // alone cannot survive a kill/restart, and the OLD behavior of
    // leaving local-file cleanup entirely to backend-completion time
    // could blank a still-loading tile. This is the exact, and ONLY,
    // moment cleanup for THIS item becomes safe (a fallback widget just
    // confirmed a genuine successful remote decode/initialization) --
    // persists `remoteDisplayReady=true` for this item, deletes its own
    // local file, and removes the whole durable overlay record once
    // every expected item is ready. See
    // `owner_optimistic_media_cleanup.dart`'s file-level lifetime
    // contract doc comment.
    if (car != null) {
      final carId = listingPrimaryId(car!);
      if (carId.isNotEmpty) {
        unawaited(_cleanupOwnerMediaAndRefreshBadge(carId, clientMediaId));
      }
    }
  }

  /// Runs the actual durable-record cleanup for [clientMediaId], then --
  /// if that cleanup just confirmed [listingId]'s whole record is now
  /// gone -- refreshes the stale `serverStillProcessing` snapshot so
  /// `_showProcessingMedia` can finally stop showing the "Processing
  /// media" badge in THIS same session, without requiring the user to
  /// navigate away and back. See `_ownerMediaRecordConfirmedGone`'s own
  /// doc comment (car_details_page_fields.dart).
  Future<void> _cleanupOwnerMediaAndRefreshBadge(
    String listingId,
    String clientMediaId,
  ) async {
    final recordGone =
        await OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup(
      listingId: listingId,
      clientMediaId: clientMediaId,
    );
    if (!recordGone || !mounted) return;
    // Still the same car/page instance this was started for? (defensive:
    // a slow cleanup call finishing after the user has since navigated
    // to a different listing in the SAME page instance must not mark
    // the WRONG listing's badge as cleared.)
    if (car == null || listingPrimaryId(car!) != listingId) return;
    if (_ownerMediaRecordConfirmedGone) return;
    setState(() => _ownerMediaRecordConfirmedGone = true);
    // The owner-media poll timer (see `_CarDetailsPageLoad
    // ._pollOwnerMediaOnce`) independently notices `_showProcessingMedia`
    // flipping false and self-cancels on its own very next tick (at most
    // `_ownerMediaPollInterval` later) -- no direct call from here, since
    // this mixin is applied before `_CarDetailsPageLoad` and has no
    // static access to its members.
  }

  /// Tracks which `clientMediaId`s currently have an in-flight
  /// [_backgroundProbeAllPendingSlots] probe, so a slot is never probed
  /// twice concurrently across overlapping calls (e.g. a poll tick firing
  /// again before a previous probe for the same slot has resolved).
  final Set<String> _backgroundProbeInFlight = <String>{};

  /// Real-device acceptance fix ("Processing media" badge never clears
  /// unless I swipe through every single photo"): [OwnerFallbackHeroImage]
  /// / [OwnerFallbackVideoThumbnail] only ever start their own
  /// remote-readiness probe from `initState`/`didUpdateWidget` -- i.e.
  /// only once Flutter actually BUILDS that hero slide. The hero gallery
  /// is a `PageView.builder` (`car_details_page_build_hero.dart`), which
  /// (per Flutter's own default viewport/cache-extent behavior) only ever
  /// builds the current slide plus a small margin -- so a slide the
  /// owner never swipes to is never built, its probe never runs, and
  /// [_showProcessingMedia]'s condition B (every expected item CONFIRMED
  /// visually rendered) can then never become satisfied through polling
  /// alone, leaving the badge stuck forever for any multi-photo listing
  /// unless the owner manually swipes all the way through -- directly
  /// contradicting this task's "auto-reconciles in the background,
  /// no manual action required" contract.
  ///
  /// This runs the EXACT SAME kind of probe directly here, independent of
  /// whether the slide widget is built, for every slot that already has
  /// a remote counterpart but has not yet been confirmed -- so the badge
  /// can clear itself purely in the background. Deliberately mirrors
  /// (does not refactor/share state with) each widget's own probe to
  /// avoid entangling this page's lifecycle with StatefulWidget-local
  /// probe state; a slide the owner DOES later swipe to simply re-probes
  /// once more on its own (cheap: `listingCachedNetworkImageProvider`
  /// already caches, and `VideoThumbnail.thumbnailData` is a fast local
  /// decode of an already-downloaded remote file) -- never a regression,
  /// just a harmless redundant confirmation.
  void _backgroundProbeAllPendingSlots() {
    final overlay = _ownerMediaOverlay;
    if (overlay == null || overlay.isEmpty) return;
    for (final slot in overlay.slots) {
      final remoteUrl = slot.remoteUrl;
      if (remoteUrl == null || remoteUrl.trim().isEmpty) continue;
      final id = slot.clientMediaId;
      if (_remoteDisplayReady[id] == true) continue;
      if (!_backgroundProbeInFlight.add(id)) continue; // already in flight
      final probe = slot.kind == OwnerMediaKind.image
          ? _backgroundProbeImageDecodes(remoteUrl)
          : _backgroundProbeVideoThumbnail(remoteUrl);
      unawaited(probe.then((ok) {
        _backgroundProbeInFlight.remove(id);
        if (ok) _markOwnerMediaRemoteDisplayReady(id);
      }));
    }
  }

  /// Image-kind half of [_backgroundProbeAllPendingSlots] -- same
  /// `ImageStream`-based decode confirmation as
  /// `OwnerFallbackHeroImage._maybeStartProbe`, just not tied to that
  /// widget's own `initState`/build lifecycle. Honors the same
  /// test-only override hook so widget tests can exercise this
  /// deterministically without a real network round trip.
  Future<bool> _backgroundProbeImageDecodes(String url) {
    final override = debugCarDetailsBackgroundImageProbeOverride;
    if (override != null) return override(url);
    final completer = Completer<bool>();
    final provider = listingCachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Video-kind half of [_backgroundProbeAllPendingSlots] -- same
  /// `VideoThumbnail.thumbnailData` confirmation as
  /// `OwnerFallbackVideoThumbnail._probe`, just not tied to that widget's
  /// own `initState`/build lifecycle. Honors the same test-only override
  /// hook so widget tests can exercise this deterministically without a
  /// real video file.
  Future<bool> _backgroundProbeVideoThumbnail(String url) async {
    final override = debugCarDetailsBackgroundVideoProbeOverride;
    if (override != null) {
      final data = await override(url);
      return data != null && data.isNotEmpty;
    }
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 80,
        timeMs: 800,
      );
      return data != null && data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// (optimistic-local-media fix) Combined "Processing media" badge rule
  /// -- see the task's own contract: show while EITHER (A) the owner's
  /// durable submission record for this listing still exists on this
  /// device (this device's own signal that the background media pipeline
  /// has not yet confirmed every expected item attached server-side --
  /// the standard `GET /api/cars/<id>` response this page already fetches
  /// does not itself expose `Car.media_status`; that field is only ever
  /// returned by the separate `/media-summary` endpoint, so the existing
  /// durable-record signal is used here instead of an extra network call)
  /// OR (B) any expected item has not yet been CONFIRMED visually
  /// rendered from its remote source on this device -- never solely from
  /// `car.images.isNotEmpty` or a "first image loaded" heuristic. For a
  /// non-owner, edit-mode listing, or listing with no active record,
  /// falls back to the pre-existing whole-listing
  /// `OwnerPendingMediaMerge.isMediaProcessing` signal (unchanged
  /// behavior for those cases -- this page never showed this badge before
  /// this fix, so there is nothing to regress).
  bool get _showProcessingMedia {
    final overlay = _ownerMediaOverlay;
    if (overlay == null || overlay.isEmpty) return _legacyMediaProcessing;
    final expected = overlay.expectedCount;
    final readyCount = overlay.slots
        .where((s) => _remoteDisplayReady[s.clientMediaId] == true)
        .length;
    final show = (overlay.serverStillProcessing &&
            !_ownerMediaRecordConfirmedGone) ||
        readyCount < expected;
    return show;
  }

  Widget _buildHeroVideoSlide(BuildContext context, int videoIndex) {
    final entries = _heroVideoEntries;
    final entry = entries[videoIndex];
    if (entry.ownerFallbackClientMediaId != null) {
      final clientMediaId = entry.ownerFallbackClientMediaId!;
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          OwnerFallbackVideoThumbnail(
            key: ValueKey('owner_fallback_video_slot|$clientMediaId'),
            localUrl: entry.ownerFallbackLocalUrl ?? entry.url,
            remoteUrl: entry.ownerFallbackRemoteUrl,
            maxWidth: 720,
            timeMs: 800,
            fillParent: true,
            onRemoteDisplayReady: () =>
                _markOwnerMediaRemoteDisplayReady(clientMediaId),
          ),
          ..._heroVideoSlideOverlayIcons(),
        ],
      );
    }
    final videoUrl = entry.url;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        NetworkVideoThumbnailPreview(
          videoUrl: videoUrl,
          maxWidth: 720,
          timeMs: 800,
          fillParent: true,
        ),
        ..._heroVideoSlideOverlayIcons(),
      ],
    );
  }

  /// Shared "VIDEO" tag + play-button overlay for [_buildHeroVideoSlide]'s
  /// two branches (plain remote preview, and the owner-fallback widget) --
  /// extracted so the optimistic-local-media fix's fallback branch does
  /// not have to duplicate this markup.
  List<Widget> _heroVideoSlideOverlayIcons() {
    return [
      Positioned(
        top: 12,
        right: 12,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'VIDEO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          padding: EdgeInsets.all(14),
          child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
        ),
      ),
    ];
  }
}
