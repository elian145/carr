part of 'sell_flow.dart';

/// Client-side media caps for a single listing (the backend also enforces limits).
const int _kSellMaxPhotos = 20;
const int _kSellMaxVideos = 3;
const int _kSellMaxDamagePhotos = 10;

/// Phase 3B: mirrors the EXACT backend hard cap
/// (`kk/video_transcoding.py::MAX_SOURCE_DURATION_SECONDS`) for a video
/// source accepted by the server-side transcode fallback. Also enforced
/// here, client-side, for EVERY picked video (not just ones needing
/// server transcode) -- never silently trimmed, never uploaded over this
/// limit through any path. If the backend limit ever changes, update
/// both together.
const int _kSellVideoMaxDurationMs = 30 * 1000;

/// Downscale/re-encode listing photos at pick time. A modern phone camera
/// produces 10-25MB frames; uploading 20 of those times out or hits the
/// server's 25MB-per-file limit. This still exceeds what the gallery displays.
const double _kSellPhotoMaxEdge = 2048;
const int _kSellPhotoQuality = 85;

/// Max simultaneous [_backfillImageDimensions]/[_backfillDamageImagePreviews]
/// jobs -- bounded so picking a large batch doesn't decode/convert dozens
/// of large images at once (real per-item memory/CPU cost from
/// `readAsBytes` + `ui.instantiateImageCodec` + HEIC->JPEG conversion).
/// High enough that a typical 5-10 photo batch still resolves in roughly
/// one "wave" of wall-clock time instead of several serial ones -- see
/// `_backfillImageDimensions`'s doc comment.
const int _kBackfillConcurrency = 4;

mixin _SellStep4Logic on _SellStep4Fields {
  @override
  void initState() {
    super.initState();
    unawaited(_loadMediaDraft());
  }

  Future<void> _loadMediaDraft() async {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final startFresh = parentState?.widget.startFreshListing == true;
    if (startFresh) {
      if (mounted) {
        setState(() {
          _selectedImages = [];
          _blurredImages = [];
          _damageImages = [];
          _selectedVideos.clear();
          _existingServerVideos = [];
          _pendingServerTranscodeVideos = [];
          _primaryImageIndex = 0;
          _imagesProcessed = false;
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData.remove('images');
        parentState.carData.remove('original_images');
        parentState.carData.remove('blurred_images');
        parentState.carData.remove('damage_images');
        parentState.carData.remove('original_damage_images');
        parentState.carData.remove('blurred_damage_images');
        parentState.carData.remove('videos');
        parentState.carData.remove('existing_video_records');
        parentState.carData.remove('server_transcode_videos');
        parentState.carData.remove('images_processed');
        parentState.carData.remove('processed_image_paths');
        parentState.carData.remove('use_blurred_plates');
        parentState.carData.remove('primary_image_index');
      }
    } else {
      final parentImages = parentState?.carData['original_images'] ??
          parentState?.carData['images'];
      final parentBlurred = parentState?.carData['blurred_images'];
      final parentDamage = parentState?.carData['original_damage_images'] ??
          parentState?.carData['damage_images'];
      final parentDamageBlurred = parentState?.carData['blurred_damage_images'];
      final parentVideos = parentState?.carData['videos'];
      // CarNet V1 batch-3: raw existing-video records (with server `id`),
      // set once by `listingToSellDraftSnapshot` when entering edit mode.
      // Not merged with picker-driven `_selectedVideos`/draft persistence --
      // this is a read/delete-only view of what's already on the server.
      final parentExistingVideoRecords =
          parentState?.carData['existing_video_records'];
      List<dynamic> stepImages = const [];
      List<dynamic> stepBlurred = const [];
      List<dynamic> stepDamage = const [];
      List<XFile> stepVideos = const [];
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString(_SellStep4Fields._draftKey);
        if (raw != null && raw.trim().isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final data = Map<String, dynamic>.from(
              decoded.cast<String, dynamic>(),
            );
            if (data['selectedImages'] is List) {
              stepImages = List<dynamic>.from(data['selectedImages'] as List);
            }
            if (data['blurredImages'] is List) {
              stepBlurred = List<dynamic>.from(data['blurredImages'] as List);
            }
            if (data['damage_images'] is List) {
              stepDamage = List<dynamic>.from(data['damage_images'] as List);
            }
            if (data['selectedVideos'] is List) {
              stepVideos = (data['selectedVideos'] as List)
                  .map(ListingImageMedia.source)
                  .where((e) => e.trim().isNotEmpty && File(e).existsSync())
                  .map((e) => XFile(e))
                  .toList();
            }
            _imagesProcessed = data['imagesProcessed'] == true;
            final draftPrimary = data['primaryImageIndex'];
            if (draftPrimary is int) {
              _primaryImageIndex = draftPrimary;
            } else {
              final parsed = int.tryParse(draftPrimary?.toString() ?? '');
              if (parsed != null) _primaryImageIndex = parsed;
            }
          }
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }

      final mergedImages = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentImages is List ? List<dynamic>.from(parentImages) : null,
        secondary: stepImages,
      );
      final mergedBlurred = SellDraftMediaPersistence.coalesceMediaLists(
        primary:
            parentBlurred is List ? List<dynamic>.from(parentBlurred) : null,
        secondary: stepBlurred,
      );
      final mergedDamage = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentDamage is List ? List<dynamic>.from(parentDamage) : null,
        secondary: stepDamage,
      );
      final mergedVideos = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentVideos is List ? List<dynamic>.from(parentVideos) : null,
        secondary: stepVideos.map((e) => e.path).toList(),
      );

      if (parentState?.carData['images_processed'] == true) {
        _imagesProcessed = true;
      }
      if (parentState != null &&
          parentState.carData['primary_image_index'] != null) {
        _primaryImageIndex = sellPrimaryImageIndex(
          parentState.carData,
          length: mergedImages.length,
        );
      }

      if (mounted) {
        setState(() {
          _selectedImages = mergedImages;
          _blurredImages = mergedBlurred;
          _damageImages = mergedDamage;
          _selectedVideos
            ..clear()
            ..addAll(ListingImageMedia.localFiles(mergedVideos));
          _existingServerVideos = parentExistingVideoRecords is List
              ? parentExistingVideoRecords
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : [];
          // Preview-decoupling fix: resume/edit-mode reload must restore
          // any pending server-transcode video previews from THIS draft's
          // own carData (item 10 -- "keep the original local path
          // available throughout the sell flow until submission
          // completes or the user removes the video"), exactly like
          // `_existingServerVideos` just above restores already-uploaded
          // server videos.
          _pendingServerTranscodeVideos = ServerTranscodeVideoSpec.listFromJson(
            parentState?.carData['server_transcode_videos'],
          );
          _clampPrimaryImageIndex();
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData['original_images'] =
            List<dynamic>.from(mergedImages);
        parentState.carData['blurred_images'] =
            List<dynamic>.from(mergedBlurred);
        parentState.carData['original_damage_images'] =
            List<dynamic>.from(mergedDamage);
        if (parentDamageBlurred is List) {
          parentState.carData['blurred_damage_images'] =
              List<dynamic>.from(parentDamageBlurred);
        }
        // Apply-choice-timing fix: re-derive the ACTIVE `images`/
        // `damage_images` lists from whatever blur choice is already
        // recorded on `use_blurred_plates`, instead of unconditionally
        // forcing them back to the originals here. This method
        // (`_loadMediaDraft`) runs from `initState`, i.e. every time this
        // Photos step widget is (re)created -- which includes revisiting
        // Photos (e.g. tapping Previous) after already having chosen
        // "blurred" on the plate-blur-choice step. Unconditionally
        // overwriting `images` with the originals here silently reverted
        // an already-made "blurred" choice back to unblurred (with
        // `use_blurred_plates` left at `true`, now mismatched with the
        // active `images` list) purely from revisiting this step, with
        // no further action from the user. Mirrors the same
        // choice-respecting pattern already used in
        // `_writeMediaListsToParent` and the background-blur completion
        // handler in `sell_car_page_plate_blur.dart`.
        if (parentState.carData['use_blurred_plates'] is bool) {
          applySellPlateBlurChoice(
            parentState.carData,
            parentState.carData['use_blurred_plates'] == true,
          );
        } else {
          parentState.carData['images'] = List<dynamic>.from(mergedImages);
          parentState.carData['damage_images'] =
              List<dynamic>.from(mergedDamage);
        }
        parentState.carData['videos'] = List<XFile>.from(
          ListingImageMedia.localFiles(mergedVideos),
        );
        parentState.carData['images_processed'] = _imagesProcessed;
        parentState.carData['primary_image_index'] = _primaryImageIndex;
        parentState.carData['sell_wizard_v2'] = true;
      }
    }
    if (_selectedImages.isNotEmpty &&
        parentState != null &&
        !parentState.hasBlurredPlatesReady &&
        !parentState.isBlurringPlates) {
      unawaited(parentState.startBackgroundPlateBlur());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentState ??= context.findAncestorStateOfType<_SellCarPageState>();
  }

  @override
  void dispose() {
    final parentState = _parentState;
    final skipPersist = LegacySellDraftPrefs.suppressPersist ||
        (parentState?._skipDraftPersistOnDispose == true);
    if (!skipPersist) {
      if (parentState != null) {
        _writeMediaListsToParent(
          parentState,
          images: _selectedImages,
          blurred: _blurredImages,
          damage: _damageImages,
          videos: _selectedVideos,
        );
      }
      unawaited(
        _saveDraft().then((_) {
          _parentState?._saveSellDraftSnapshot();
        }),
      );
    }
    super.dispose();
  }

  Future<void> _saveDraft() async {
    try {
      if (LegacySellDraftPrefs.suppressPersist ||
          _parentState?._skipDraftPersistOnDispose == true) {
        return;
      }
      final epoch = LegacySellDraftPrefs.persistEpoch;
      final parentState =
          _parentState ?? context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';
      final images = await SellDraftMediaPersistence.persistDynamicMediaList(
        _selectedImages,
        draftId: draftId,
        namePrefix: 'listing_orig',
      );
      final blurred = await SellDraftMediaPersistence.persistDynamicMediaList(
        _blurredImages,
        draftId: draftId,
        namePrefix: 'listing_blur',
      );
      final damage = await SellDraftMediaPersistence.persistDynamicMediaList(
        _damageImages,
        draftId: draftId,
        namePrefix: 'damage',
      );
      final videos = await SellDraftMediaPersistence.persistDynamicMediaList(
        _selectedVideos,
        draftId: draftId,
        namePrefix: 'video',
      );
      // Discard may have started while media files were being copied.
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch) ||
          parentState?._skipDraftPersistOnDispose == true) {
        return;
      }
      final resolvedImages = _persistedOrLiveMedia(_selectedImages, images);
      final resolvedBlurred = _persistedOrLiveMedia(_blurredImages, blurred);
      final resolvedDamage = _persistedOrLiveMedia(_damageImages, damage);
      final resolvedVideos = _persistedOrLiveMedia(
        _selectedVideos.map((f) => f.path).toList(),
        videos,
      );
      if (mounted) {
        setState(() {
          _selectedImages = resolvedImages;
          _blurredImages = resolvedBlurred;
          _damageImages = resolvedDamage;
          _selectedVideos
            ..clear()
            ..addAll(ListingImageMedia.localFiles(resolvedVideos));
        });
      }
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await sp.setString(
        _SellStep4Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedImages': resolvedImages
              .map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : ListingImageMedia.map(e),
              )
              .toList(),
          'blurredImages': resolvedBlurred
              .map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : ListingImageMedia.map(e),
              )
              .toList(),
          'damage_images': resolvedDamage.map(ListingImageMedia.source).toList(),
          'selectedVideos': resolvedVideos.map(ListingImageMedia.source).toList(),
          'imagesProcessed': _imagesProcessed,
          'primaryImageIndex': _primaryImageIndex,
        }),
      );
      if (parentState != null) {
        _writeMediaListsToParent(
          parentState,
          images: resolvedImages,
          blurred: resolvedBlurred,
          damage: resolvedDamage,
          videos: ListingImageMedia.localFiles(resolvedVideos),
        );
      }
      unawaited(parentState?._saveSellDraftSnapshot());
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  Future<void> _syncMediaDraftToParent() async {
    // Stale-media-after-delete fix (spec test F: "delete while durable
    // persistence is pending"): this method is fire-and-forget
    // (`unawaited`) from every pick's background chain AND every delete
    // handler, and does real, multi-second file I/O below -- so two
    // calls CAN genuinely overlap (e.g. delete one of several just-
    // picked photos before their own pick's sync below has finished).
    // Capture this call's generation NOW; if a NEWER call has since
    // started by the time this one is about to write its result, this
    // (now-superseded, possibly built from a pre-deletion snapshot)
    // result must be discarded rather than applied -- otherwise whichever
    // overlapping call's `setState` happens to land LAST would silently
    // resurrect anything removed in the meantime, regardless of which
    // call actually reflects the CURRENT, authoritative selection.
    final gen = ++_mediaSyncGeneration;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    final draftId = parentState._currentDraftId;
    // Latent concurrency fix, surfaced by the same overlapping-calls
    // scenario this generation guard exists for: `_selectedImages`/
    // `_blurredImages`/`_damageImages` are mutated IN PLACE by
    // `_removePhotoAt`/`_pickImages` etc. (`removeAt`, `[..., ...]`
    // reassignment followed by further in-place edits elsewhere) --
    // iterating the LIVE list directly here while a CONCURRENT call (a
    // delete or another pick) mutates the same list object underneath it
    // throws `ConcurrentModificationError` deep inside
    // `persistDynamicMediaList`. Snapshotting with `List.of(...)` here
    // gives this call's own iteration a stable, private copy, regardless
    // of what any other overlapping call does to the live fields
    // afterward.
    final images = await SellDraftMediaPersistence.persistDynamicMediaList(
      List<dynamic>.of(_selectedImages),
      draftId: draftId,
      namePrefix: 'listing_orig',
    );
    final blurred = await SellDraftMediaPersistence.persistDynamicMediaList(
      List<dynamic>.of(_blurredImages),
      draftId: draftId,
      namePrefix: 'listing_blur',
    );
    final damage = await SellDraftMediaPersistence.persistDynamicMediaList(
      List<dynamic>.of(_damageImages),
      draftId: draftId,
      namePrefix: 'damage',
    );
    final videos = await SellDraftMediaPersistence.persistDynamicMediaList(
      List<XFile>.of(_selectedVideos),
      draftId: draftId,
      namePrefix: 'video',
    );
    final resolvedImages = _persistedOrLiveMedia(_selectedImages, images);
    final resolvedBlurred = _persistedOrLiveMedia(_blurredImages, blurred);
    final resolvedDamage = _persistedOrLiveMedia(_damageImages, damage);
    final resolvedVideos = _persistedOrLiveMedia(
      _selectedVideos.map((f) => f.path).toList(),
      videos,
    );
    if (!mounted) return;
    if (gen != _mediaSyncGeneration) {
      // A newer sync call has started since this one began -- this
      // result is stale (it may have been built from a `_selectedImages`
      // snapshot that still included something since deleted). Drop it
      // silently; the newer call's own result is authoritative and will
      // write/has already written in its place.
      return;
    }
    setState(() {
      _selectedImages = resolvedImages;
      _blurredImages = resolvedBlurred;
      _damageImages = resolvedDamage;
      _selectedVideos
        ..clear()
        ..addAll(ListingImageMedia.localFiles(resolvedVideos));
    });
    _writeMediaListsToParent(
      parentState,
      images: resolvedImages,
      blurred: resolvedBlurred,
      damage: resolvedDamage,
      videos: ListingImageMedia.localFiles(resolvedVideos),
    );
    if (_imagesProcessed && resolvedBlurred.isNotEmpty) {
      parentState.carData['processed_image_paths'] = resolvedBlurred
          .map(ListingImageMedia.source)
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } else {
      parentState.carData.remove('processed_image_paths');
    }
    parentState.setState(() {});
    unawaited(parentState._saveSellDraftSnapshot());
  }

  String _imagePathKey(dynamic item) => ListingImageMedia.source(item);

  /// Stale-media-after-delete fix: prunes an async-populated,
  /// blur-result-shaped list (`_blurredImages`, or any
  /// `carData['blurred_images']`/`['blurred_damage_images']` snapshot) down
  /// to only the entries that correspond to a photo in [currentSelection]
  /// -- by `_ui_media_id` when BOTH sides carry one (the robust,
  /// identity-based match this fix exists for -- see
  /// `ListingImageMedia.map`'s doc comment), falling back to matching by
  /// `source` path for any item that predates this field entirely (e.g.
  /// already-remote edit-mode photos loaded from the backend, or a draft
  /// restored before this fix shipped). An entry whose id/path matches
  /// NEITHER a current id NOR a current path belongs to a photo no longer
  /// in [currentSelection] -- i.e. a deleted photo -- and is dropped.
  ///
  /// Deliberately a FILTER, never a re-sort: every surviving entry keeps
  /// its original relative order from [blurred], which already matches
  /// [currentSelection]'s order (both are ultimately derived from the same
  /// positional `originals` list at blur-merge time) -- see spec item 8,
  /// "background completion order must never become gallery order".
  List<dynamic> _pruneBlurredToCurrentSelection(
    List<dynamic> blurred,
    List<dynamic> currentSelection,
  ) {
    if (blurred.isEmpty) return blurred;
    final currentIds = currentSelection
        .map(ListingImageMedia.uiMediaId)
        .whereType<String>()
        .toSet();
    final currentPaths = currentSelection.map(_imagePathKey).toSet();
    return blurred.where((item) {
      final id = ListingImageMedia.uiMediaId(item);
      if (id != null) return currentIds.contains(id);
      return currentPaths.contains(_imagePathKey(item));
    }).toList();
  }

  /// Stale-write-after-resolution fix (spec test D; see the call site in
  /// `_writeMediaListsToParent`): merges [incoming] (THIS call's own,
  /// possibly-stale `_blurredImages` snapshot) with [existingRaw]
  /// (`parentState.carData['blurred_images']` as it stands RIGHT NOW,
  /// which `_publishBlurProgress` -- a separate, direct writer -- may
  /// have already resolved further than [incoming] knows about) --
  /// keyed by [images]' own identity order, so the result is ALSO
  /// pruned/re-aligned to the CURRENT selection as a side effect (belt-
  /// and-suspenders with `_pruneBlurredToCurrentSelection`).
  ///
  /// Per matched identity: whichever side is already resolved (missing
  /// `blur_pending`) wins; if BOTH or NEITHER are resolved, [incoming]'s
  /// entry wins (preserves the original "local/freshly-persisted value
  /// wins" behavior for the common, non-racing case -- e.g. a genuinely
  /// NEWER local result that simply hasn't been echoed into
  /// `carData['blurred_images']` yet). An identity present in [images]
  /// but in NEITHER source is simply omitted (nothing to show yet).
  List<dynamic> _preferResolvedBlurred(
    List<dynamic> incoming,
    dynamic existingRaw,
    List<dynamic> images,
  ) {
    final existing = existingRaw is List ? existingRaw : const <dynamic>[];
    bool isResolved(dynamic item) =>
        !(item is Map && item['blur_pending'] == true);
    String keyOf(dynamic item) =>
        ListingImageMedia.uiMediaId(item) ?? _imagePathKey(item);

    final incomingByKey = <String, dynamic>{};
    for (final item in incoming) {
      incomingByKey[keyOf(item)] = item;
    }
    final existingByKey = <String, dynamic>{};
    for (final item in existing) {
      existingByKey[keyOf(item)] = item;
    }

    final result = <dynamic>[];
    for (final image in images) {
      final key = keyOf(image);
      final incomingItem = incomingByKey[key];
      final existingItem = existingByKey[key];
      if (incomingItem != null && isResolved(incomingItem)) {
        result.add(incomingItem);
      } else if (existingItem != null && isResolved(existingItem)) {
        result.add(existingItem);
      } else if (incomingItem != null) {
        result.add(incomingItem);
      } else if (existingItem != null) {
        result.add(existingItem);
      }
      // Else: no entry for this identity on either side yet -- omit.
    }
    return result;
  }

  /// Keep live picker files when a persist pass drops unreadable paths.
  List<dynamic> _persistedOrLiveMedia(
    List<dynamic> live,
    List<dynamic> persisted,
  ) {
    if (live.isEmpty) return persisted;
    if (persisted.isEmpty) return live;
    if (persisted.length >= live.length) return persisted;
    return SellDraftMediaPersistence.mergeRawMediaLists([persisted, live]);
  }

  void _writeMediaListsToParent(
    _SellCarPageState parentState, {
    required List<dynamic> images,
    required List<dynamic> blurred,
    required List<dynamic> damage,
    required List<XFile> videos,
  }) {
    parentState.carData['original_images'] = List<dynamic>.from(images);
    parentState.carData['original_damage_images'] =
        List<dynamic>.from(damage);
    parentState.carData['videos'] = List<XFile>.from(videos);
    parentState.carData['primary_image_index'] = _primaryImageIndex;
    parentState.carData['sell_wizard_v2'] = true;

    // Don't wipe parent blurred results while background blur is running or
    // when this step still has an empty local blurred cache.
    final parentBlurred = parentState.carData['blurred_images'];
    if (blurred.isNotEmpty) {
      // Stale-write-after-resolution fix (spec test D): [blurred] here is
      // THIS call's own `_blurredImages` snapshot, captured whenever this
      // (possibly long-running, delete-triggered) sync started -- it can
      // still be the PENDING blur skeleton (`blur_pending: true`) even
      // though `_publishBlurProgress` (an entirely separate, direct-to-
      // `carData` writer -- see its own doc comment) has, in the
      // meantime, already resolved some/all of those same photos'
      // results into `parentBlurred`. Blindly overwriting with [blurred]
      // would silently revert an already-resolved result back to
      // "pending", and since nothing re-resolves it afterward, it would
      // stay visibly wrong (or, worse, if even less fresh, reintroduce a
      // DELETED photo's leftover entry -- the resurrection bug this whole
      // fix targets). Prefer whichever side is actually RESOLVED
      // (missing the `blur_pending` flag) per position; only fall back to
      // [blurred] when neither side is resolved yet (preserves the
      // original "local wins" behavior for the common, non-racing case).
      final merged = _preferResolvedBlurred(blurred, parentBlurred, images);
      parentState.carData['blurred_images'] = merged;
      parentState.carData['images_processed'] = true;
      _imagesProcessed = true;
      _blurredImages = merged;
    } else if (parentState.isBlurringPlates) {
      // Keep existing blurred_images / processed flag untouched.
    } else if (parentBlurred is List && parentBlurred.isNotEmpty) {
      parentState.carData['images_processed'] = true;
      _imagesProcessed = true;
      _blurredImages = List<dynamic>.from(parentBlurred);
    } else {
      parentState.carData['blurred_images'] = <dynamic>[];
      parentState.carData['images_processed'] = _imagesProcessed;
    }

    // Keep damage active list as originals until blur-choice applies.
    // Preserve any already-blurred damage produced by the parent job.
    final parentDamageBlurred = parentState.carData['blurred_damage_images'];
    if (!parentState.isBlurringPlates &&
        (parentDamageBlurred is! List || parentDamageBlurred.isEmpty) &&
        damage.isEmpty) {
      parentState.carData['blurred_damage_images'] = <dynamic>[];
    }

    final useBlur = parentState.carData['use_blurred_plates'] == true;
    if (useBlur) {
      applySellPlateBlurChoice(parentState.carData, true);
    } else {
      parentState.carData['images'] = List<dynamic>.from(images);
      parentState.carData['damage_images'] = List<dynamic>.from(damage);
    }
  }

  /// [logContext] is purely a diagnostic-log tag (e.g. `'[DAMAGE]'` for
  /// damage photos) appended after `[HEIC PREVIEW]` -- it has no effect on
  /// behavior. Defaults to empty so the listing-photo call site below logs
  /// exactly as before.
  Future<Map<String, dynamic>> _pickedImageMedia(
    XFile file, {
    required String draftId,
    String logContext = '',
    String? uiMediaId,
  }) async {
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e, st) {
      logNonFatal(e, st);
    }
    final isHeic = HeicPreviewConverter.isHeic(file.path);
    // HEIC/HEIF fix (real-device evidence): Flutter's Skia decoders --
    // `ui.instantiateImageCodec` below, and the `Image.file`/`Image.memory`
    // widgets the Step4 grid / blur-choice "Original photos" grid use --
    // cannot decode HEIC/HEIF at all, even though `readAsBytes()` above
    // succeeds. Generate a JPEG preview via the OS's own native decoder so
    // local rendering has something Skia can actually display. The
    // original HEIC/HEIF file/path is completely untouched here -- it
    // stays the only thing `ListingImageMedia.source()`/`localFile()`
    // (and therefore upload/submission) ever return.
    //
    // Reused as-is for damage photos (via `logContext: '[DAMAGE]'` from
    // `_backfillDamageImagePreviews`) -- this function has no listing-only
    // behavior, so there is nothing damage-specific to branch on here.
    String? previewSource;
    if (bytes != null && isHeic) {
      previewSource = await HeicPreviewConverter.ensureJpegPreview(
        bytes,
        draftId: draftId,
      );
    }
    int? width;
    int? height;
    if (bytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (e, st) {
        // Expected/harmless for HEIC/HEIF -- Skia can't decode it either,
        // same root cause `previewSource` above just worked around. Width/
        // height simply stay null, which every consumer already tolerates
        // (aspect-ratio hinting only). Only report non-fatals for
        // unexpected decode failures on non-HEIC files.
        if (!isHeic) logNonFatal(e, st);
      }
    }
    _debugLog(
      '[HEIC PREVIEW]$logContext originalSource=${file.path}',
    );
    _debugLog(
      '[HEIC PREVIEW]$logContext previewSource=$previewSource',
    );
    return ListingImageMedia.map(
      file,
      width: width,
      height: height,
      previewSource: previewSource,
      uiMediaId: uiMediaId,
    );
  }

  /// Decodes width/height (and, for HEIC/HEIF, generates a local JPEG
  /// preview -- see `HeicPreviewConverter`) for freshly-picked photos and
  /// backfills them onto the matching `_selectedImages` entry (matched by
  /// path, so it stays correct even if the user removes/reorders photos
  /// while this is still running -- see A-fix item 9, "removing/reordering
  /// images keeps mappings correct"; a removed photo's `indexWhere` below
  /// simply returns -1 and is skipped, so it is never resurrected). Never
  /// blocks or delays the original's first render -- that already
  /// happened in `_pickImages`'s first `setState`, before this is ever
  /// called.
  ///
  /// Runs with bounded concurrency (see [_kBackfillConcurrency]) instead
  /// of one file at a time (one-by-one-appearance fix -- real-device
  /// evidence: "images appear slowly one-by-one while background
  /// processing/upload is happening"). Every picked photo's *slot* is
  /// already visible the instant `_pickImages` returns, but a HEIC/HEIF
  /// photo specifically has nothing decodable to show in that slot (see
  /// `sell_step4_build_photos.dart`'s `previewLocalFile` fallback to the
  /// raw, Skia-undecodable HEIC path) until THIS method reaches it and
  /// supplies a `previewSource`. A strictly serial loop therefore revealed
  /// real HEIC thumbnails one at a time, each roughly N x (one file's
  /// conversion time) after the previous -- visually indistinguishable
  /// from "appearing slowly one-by-one" even though every grid slot was
  /// already present from the very first frame. Running several
  /// conversions concurrently instead means thumbnails resolve close
  /// together rather than in a strict chain, without decoding/converting
  /// an unbounded number of large images at once.
  ///
  /// Must run, and be awaited, BEFORE `_syncMediaDraftToParent()`: that
  /// durable-copies each file, which *rewrites* `ListingImageMedia.source`
  /// to a new `sell_draft_media/...` path -- if this ran afterward (as it
  /// used to, unawaited), the by-path match below would already always
  /// fail to find the (renamed) entry, silently dropping the backfill.
  Future<void> _backfillImageDimensions(
    List<XFile> files, {
    required String draftId,
    required Map<String, String> uiMediaIdsByPath,
  }) async {
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (!mounted) return;
        final i = nextIndex++;
        if (i >= files.length) return;
        final file = files[i];
        final uiMediaId = uiMediaIdsByPath[file.path];
        // Mark pending BEFORE the (possibly multi-second) conversion work
        // so the grid tile can show a spinner instead of attempting to
        // decode the raw HEIC file. Non-HEIC files never need a preview,
        // so skip the extra setState for them.
        final isHeic = HeicPreviewConverter.isHeic(file.path);
        if (isHeic && mounted) {
          setState(() => _heicPreviewPending.add(file.path));
        }
        try {
          final enriched = await _pickedImageMedia(
            file,
            draftId: draftId,
            uiMediaId: uiMediaId,
          );
          if (!mounted) return;
          // Stale-media-after-delete guard (spec item 5/6): even though
          // the by-path match below already safely no-ops if this item
          // was deleted (`idx == -1`), ALSO verify by identity -- a
          // re-pick of the exact same path (spec item 7's "delete then
          // re-add the same file") would otherwise still path-match the
          // NEW item's slot and incorrectly apply THIS (old, now-stale)
          // pick's result onto it.
          final idx = _selectedImages.indexWhere(
            (item) =>
                ListingImageMedia.source(item) == file.path &&
                (uiMediaId == null ||
                    ListingImageMedia.uiMediaId(item) == uiMediaId),
          );
          _debugLog('[HEIC PREVIEW] applying path=${file.path}');
          _debugLog(
            '[HEIC PREVIEW] previewSource before='
            '${idx == -1 ? null : ListingImageMedia.previewSource(_selectedImages[idx])}',
          );
          _debugLog(
            '[HEIC PREVIEW] previewSource after='
            '${ListingImageMedia.previewSource(enriched)}',
          );
          _debugLog('[HEIC PREVIEW] matched=${idx != -1}');
          if (idx == -1) continue;
          // In-place replace only -- never remove/reinsert/reorder, so the
          // already-visible slot's position and identity never change,
          // only its content (raw HEIC path -> decodable preview, plus
          // width/height) once this item's own work finishes. Clear the
          // pending marker in the SAME setState so the tile never flashes
          // an intermediate "pending but still raw HEIC" frame.
          setState(() {
            _selectedImages[idx] = enriched;
            _heicPreviewPending.remove(file.path);
          });
        } finally {
          // Safety net: guarantees the pending marker is never left stuck
          // (which would spin forever) even if something above throws
          // unexpectedly. Harmless no-op if already removed above.
          if (isHeic && mounted) {
            setState(() => _heicPreviewPending.remove(file.path));
          }
        }
      }
    }

    final workerCount = _kBackfillConcurrency < files.length
        ? _kBackfillConcurrency
        : files.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  /// Damage-photo counterpart to [_backfillImageDimensions] above: reuses
  /// the exact same [_pickedImageMedia] helper (and therefore the exact
  /// same [HeicPreviewConverter]) to generate a JPEG preview for HEIC/HEIF
  /// damage photos, then backfills it onto the matching `_damageImages`
  /// entry by path.
  ///
  /// Damage photos previously never went through `_pickedImageMedia` at
  /// all -- `_pickDamageImages` inserted the raw picked `XFile`s directly,
  /// so no `preview_source` was ever generated for them, which is why a
  /// HEIC/HEIF damage photo never rendered even after the equivalent fix
  /// already shipped for listing photos.
  ///
  /// Must run, and be awaited, BEFORE `_syncMediaDraftToParent()` for the
  /// exact same reason documented on `_backfillImageDimensions`: that call
  /// durable-copies each file and rewrites `source`, so a by-path match
  /// here would silently fail to find the (renamed) entry if this ran
  /// afterward.
  Future<void> _backfillDamageImagePreviews(
    List<XFile> files, {
    required String draftId,
    required Map<String, String> uiMediaIdsByPath,
  }) async {
    // Bounded-concurrency fix, same rationale as `_backfillImageDimensions`
    // above -- see that method's doc comment.
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (!mounted) return;
        final i = nextIndex++;
        if (i >= files.length) return;
        final file = files[i];
        final uiMediaId = uiMediaIdsByPath[file.path];
        final enriched = await _pickedImageMedia(
          file,
          draftId: draftId,
          logContext: '[DAMAGE]',
          uiMediaId: uiMediaId,
        );
        if (!mounted) return;
        // Same identity re-verification as `_backfillImageDimensions` --
        // see that method's doc comment (spec item 7: delete-then-re-add
        // of the same file must not let this stale result attach to the
        // new pick's entry).
        final idx = _damageImages.indexWhere(
          (item) =>
              ListingImageMedia.source(item) == file.path &&
              (uiMediaId == null ||
                  ListingImageMedia.uiMediaId(item) == uiMediaId),
        );
        _debugLog('[HEIC PREVIEW][DAMAGE] applying path=${file.path}');
        _debugLog(
          '[HEIC PREVIEW][DAMAGE] previewSource before='
          '${idx == -1 ? null : ListingImageMedia.previewSource(_damageImages[idx])}',
        );
        _debugLog(
          '[HEIC PREVIEW][DAMAGE] previewSource after='
          '${ListingImageMedia.previewSource(enriched)}',
        );
        _debugLog('[HEIC PREVIEW][DAMAGE] matched=${idx != -1}');
        if (idx == -1) continue;
        setState(() => _damageImages[idx] = enriched);
      }
    }

    final workerCount = _kBackfillConcurrency < files.length
        ? _kBackfillConcurrency
        : files.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  /// Removes the photo at [index] from the wizard's local media state.
  ///
  /// If this photo already exists on the server (has a backend image id and
  /// we're editing an existing listing), the server row/storage object is
  /// deleted first; the local list is only updated once that succeeds so a
  /// failed delete (e.g. the last-photo invariant, or a network error) never
  /// leaves the UI showing a photo that's actually still live on the server,
  /// or drops a photo from the draft when it wasn't actually deleted.
  Future<void> _removePhotoAt(int index) async {
    if (index < 0 || index >= _selectedImages.length) return;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final image = _selectedImages[index];
    final imageId = ListingImageMedia.id(image);
    final editListingId = parentState?._editListingId;
    final isEditMode = parentState?._isEditMode == true;

    if (imageId != null && isEditMode && editListingId != null) {
      // Bug-3 instrumentation (real-device trace): this is the ONLY place
      // in the Sell flow that deletes a server-attached image, and it only
      // ever runs from this explicit, user-initiated "remove photo" tap in
      // the edit-mode wizard grid -- never from `PendingSellSubmissionService`
      // resume/background-foreground/force-close logic, which never calls
      // any delete endpoint (see that file's docs).
      _debugLog(
        '[SELL MEDIA] delete image carId=$editListingId mediaId=$imageId '
        'reason=user_removed_in_edit_mode',
      );
      try {
        await ApiService.deleteCarImage(editListingId, imageId);
      } catch (e, st) {
        logNonFatal(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                userErrorText(
                  context,
                  e,
                  fallback:
                      AppLocalizations.of(context)?.errorTitle ?? 'Error',
                ),
              ),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedImages.removeAt(index);
      _onImageRemovedAt(index);
    });
    parentState?.carData.remove('use_blurred_plates');
    // Stale-media-after-delete fix (PRIMARY root cause -- the async race):
    // synchronously publish the post-deletion `_selectedImages` into
    // `carData` BEFORE invalidating/restarting the blur job below. Without
    // this, `invalidatePlateBlurJob()` + `startBackgroundPlateBlur()` fire
    // `unawaited` immediately, and the NEW job's `_plateBlurOriginals()`
    // reads `carData['original_images']` SYNCHRONOUSLY at that instant --
    // but the only OTHER writer of that key, `_syncMediaDraftToParent()`
    // below, is itself async (real, multi-second durable-copy file I/O)
    // and had not run yet by then. The new job therefore started from the
    // STALE, pre-deletion list, computed (and later published) a blur
    // result for the deleted photo too, directly reintroducing it into
    // both `carData['original_images']` and `['blurred_images']`. Writing
    // synchronously here closes that window: by the time the new job is
    // even enqueued, `carData` already reflects the deletion.
    //
    // `carData['blurred_images']` must be pruned from ITS OWN current
    // value, NOT from Step4's local `_blurredImages` field: a background
    // blur job's progress (`_publishBlurProgress`,
    // `sell_car_page_plate_blur.dart`) writes DIRECTLY into
    // `carData['blurred_images']` and never touches `_blurredImages` at
    // all -- so `_blurredImages` can be stale (e.g. still empty/a pending
    // skeleton) even while `carData['blurred_images']` already holds a
    // fresh, genuinely-resolved result. Pruning/writing from `_blurredImages`
    // instead would silently throw that fresh result away.
    if (parentState != null) {
      parentState.carData['original_images'] = List<dynamic>.from(
        _selectedImages,
      );
      final currentBlurred = parentState.carData['blurred_images'];
      if (currentBlurred is List && currentBlurred.isNotEmpty) {
        final pruned = _pruneBlurredToCurrentSelection(
          List<dynamic>.from(currentBlurred),
          _selectedImages,
        );
        parentState.carData['blurred_images'] = pruned;
        if (mounted) setState(() => _blurredImages = pruned);
      } else if (_selectedImages.isEmpty) {
        if (mounted) {
          setState(() {
            _blurredImages = [];
            _imagesProcessed = false;
          });
        }
      } else {
        // `_blurredImages` may still carry its own stale entries (e.g. a
        // pending skeleton for a now-deleted item) even when the
        // parent's `blurred_images` is empty -- prune it the same way so
        // a LATER `_writeMediaListsToParent` call never adopts it as-is.
        final pruned = _pruneBlurredToCurrentSelection(
          _blurredImages,
          _selectedImages,
        );
        if (mounted) setState(() => _blurredImages = pruned);
      }
    }
    // `clearBlurred: false` -- unlike its other callers, this one already
    // correctly PRUNED `carData['blurred_images']` immediately above
    // (keeping every still-selected photo's genuinely-resolved result);
    // the default `clearBlurred: true` would otherwise wipe that out
    // again right here, discarding valid results for photos that were
    // NOT deleted. The job id still bumps (`_plateBlurJobId++`) and
    // `isBlurringPlates` still resets, so any OLD in-flight job's
    // progress is still correctly ignored once it resolves.
    parentState?.invalidatePlateBlurJob(clearBlurred: false);
    parentState?.invalidatePhotoPrestage();
    unawaited(_syncMediaDraftToParent());
    if (_selectedImages.isNotEmpty) {
      unawaited(parentState?.startBackgroundPlateBlur());
    }
  }

  /// Damage-photo counterpart to [_removePhotoAt] -- same stale-media-
  /// after-delete fixes (synchronous `carData` pre-write to close the
  /// async race before restarting the blur job; identity-based pruning of
  /// any already-blurred damage result for the deleted photo), used by
  /// `sell_step4_build_damage.dart`'s remove button in place of the
  /// previous inline `_damageImages.removeAt(index)` handler (which had
  /// neither protection).
  void _removeDamagePhotoAt(int index) {
    if (index < 0 || index >= _damageImages.length) return;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    setState(() {
      _damageImages.removeAt(index);
    });
    parentState?.carData.remove('use_blurred_plates');
    // Same PRIMARY-root-cause race fix as `_removePhotoAt`: publish the
    // post-deletion damage list (and a prior-blurred-damage-result list
    // pruned to match it) into `carData` synchronously, before the new
    // blur job below can read `carData['original_damage_images']`.
    if (parentState != null) {
      parentState.carData['original_damage_images'] = List<dynamic>.from(
        _damageImages,
      );
      final existingBlurred =
          parentState.carData['blurred_damage_images'];
      if (existingBlurred is List && existingBlurred.isNotEmpty) {
        parentState.carData['blurred_damage_images'] =
            _pruneBlurredToCurrentSelection(existingBlurred, _damageImages);
      }
    }
    // `clearBlurred: false` -- see `_removePhotoAt`'s identical comment;
    // `carData['blurred_damage_images']` was already correctly pruned
    // immediately above.
    parentState?.invalidatePlateBlurJob(clearBlurred: false);
    parentState?.invalidatePhotoPrestage();
    unawaited(_syncMediaDraftToParent());
    if (_damageImages.isNotEmpty || _selectedImages.isNotEmpty) {
      unawaited(parentState?.startBackgroundPlateBlur());
    }
  }

  /// Deletes an already-uploaded video (shown while editing an existing
  /// listing) from the backend, then removes it locally on success.
  ///
  /// Optimistic-with-rollback: the server call happens first; the tile
  /// only disappears once the delete actually succeeds, and a failure
  /// leaves `_existingServerVideos` untouched and surfaces the existing
  /// Sell-flow error snackbar, so a removed-looking-but-still-live video
  /// can never reappear later and confuse the seller.
  Future<void> _removeExistingVideoAt(int index) async {
    if (index < 0 || index >= _existingServerVideos.length) return;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final editListingId = parentState?._editListingId;
    if (editListingId == null) return;
    final video = _existingServerVideos[index];
    final videoId = ListingImageMedia.id(video);
    if (videoId == null) return;

    // Bug-3 instrumentation (real-device trace): same explicit,
    // user-initiated-only delete guarantee as `_removePhotoAt` above --
    // never reachable from resume/background/foreground logic.
    _debugLog(
      '[SELL MEDIA] delete video carId=$editListingId mediaId=$videoId '
      'reason=user_removed_in_edit_mode',
    );
    try {
      await ApiService.deleteCarVideo(editListingId, videoId);
    } catch (e, st) {
      logNonFatal(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorText(
                context,
                e,
                fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
              ),
            ),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _existingServerVideos.removeAt(index);
    });
    if (parentState != null) {
      parentState.carData['existing_video_records'] = List<dynamic>.from(
        _existingServerVideos,
      );
    }
  }

  void _setPrimaryImage(int index) {
    if (index < 0 || index >= _selectedImages.length) return;
    if (index == _primaryImageIndex) return;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    setState(() {
      _primaryImageIndex = index;
    });
    parentState?.carData['primary_image_index'] = _primaryImageIndex;
    unawaited(_syncMediaDraftToParent());
    unawaited(_saveDraft());
  }

  void _showListingMediaLimitSnack({
    bool isVideo = false,
    bool isDamage = false,
  }) {
    if (!mounted) return;
    final code = Localizations.localeOf(context).languageCode;
    final max = isDamage
        ? _kSellMaxDamagePhotos
        : isVideo
            ? _kSellMaxVideos
            : _kSellMaxPhotos;
    String msg;
    if (isDamage) {
      if (code == 'ar') {
        msg = 'يمكنك إضافة حتى $max صورة ضرر لكل إعلان.';
      } else if (code == 'ku' || code == 'ckb') {
        msg = 'دەتوانیت تا $max وێنەی زیان بۆ هەر ڕیکلامێک زیاد بکەیت.';
      } else {
        msg = 'You can add up to $max damage photos per listing.';
      }
    } else if (isVideo) {
      if (code == 'ar') {
        msg = 'يمكنك إضافة حتى $max مقاطع فيديو لكل إعلان.';
      } else if (code == 'ku' || code == 'ckb') {
        msg = 'دەتوانیت تا $max ڤیدیۆ بۆ هەر ڕیکلامێک زیاد بکەیت.';
      } else {
        msg = 'You can add up to $max videos per listing.';
      }
    } else {
      if (code == 'ar') {
        msg = 'يمكنك إضافة حتى $max صورة لكل إعلان.';
      } else if (code == 'ku' || code == 'ckb') {
        msg = 'دەتوانیت تا $max وێنە بۆ هەر ڕیکلامێک زیاد بکەیت.';
      } else {
        msg = 'You can add up to $max photos per listing.';
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImages() async {
    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: _kSellPhotoMaxEdge,
        maxHeight: _kSellPhotoMaxEdge,
        imageQuality: _kSellPhotoQuality,
      );
      if (files.isEmpty || !mounted) return;
      final existing = _selectedImages.map(_imagePathKey).toSet();
      var newFiles = files.where((f) => !existing.contains(f.path)).toList();
      // Enforce a per-listing photo cap client-side.
      final remaining = _kSellMaxPhotos - _selectedImages.length;
      final bool overLimit = newFiles.length > remaining;
      if (overLimit) {
        newFiles = newFiles.take(remaining < 0 ? 0 : remaining).toList();
      }
      if (newFiles.isEmpty) {
        if (overLimit) _showListingMediaLimitSnack(isVideo: false);
        return;
      }
      setState(() => _isImportingMedia = true);
      try {
        // A-fix (real-device evidence): insert the ORIGINAL picked photos
        // into state IMMEDIATELY -- no `await` between the picker
        // returning and this `setState`, exactly like `_pickDamageImages`
        // already does below. This used to `await Future.wait(newFiles.
        // map(_pickedImageMedia))` first -- an image decode per file, for
        // width/height metadata only -- BEFORE the very first setState,
        // which delayed the original's first render by however long that
        // decode took (worse for `content://` sources, which must read
        // through `XFile.readAsBytes()`). Width/height are cosmetic
        // (aspect-ratio hinting only; every consumer already tolerates
        // them being absent), so they're now backfilled in the background
        // via `_backfillImageDimensions`, after the original is already
        // visible -- never blocking it.
        for (final f in newFiles) {
          _debugLog(
            'PHOTO PICK: path=${f.path} name=${f.name} '
            'contentUri=${f.path.startsWith('content://')}',
          );
        }
        // Stale-media-after-delete fix: assign each freshly-picked file a
        // permanent `_ui_media_id` NOW, derived from its picker path PLUS
        // a monotonic sequence number (`_uiMediaSeq`) -- so re-picking the
        // exact same path after deleting it still gets a brand-new id,
        // never the deleted one's (spec requirement: add/remove/re-add
        // must never let an old async result attach to the new pick).
        // `uiMediaIdsByPath` lets `_backfillImageDimensions` below look up
        // the SAME id for the SAME file later (recomputing it from the
        // path alone would be fine for a per-path-only scheme, but NOT
        // once a sequence number is mixed in, since that number is only
        // known here, at assignment time).
        final uiMediaIdsByPath = <String, String>{};
        final additions = newFiles.map((f) {
          final id = SellMediaIdentity.stableIdFromSeed(
            'listing:${f.path}:${_uiMediaSeq++}',
          );
          uiMediaIdsByPath[f.path] = id;
          return ListingImageMedia.map(f, uiMediaId: id);
        }).toList();
        if (!mounted) return;
        if (additions.isEmpty) {
          setState(() => _isImportingMedia = false);
          return;
        }
        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
        setState(() {
          _selectedImages = [..._selectedImages, ...additions];
          _imagesProcessed = false;
          _blurredImages = [];
          _isProcessingImages = false;
          // One-by-one-appearance fix (real-device evidence: "after I
          // choose multiple images, they appear slowly one-by-one while
          // background processing/upload is happening"): publication of
          // every selected slot is already complete at this point --
          // nothing above this `setState` awaited any I/O. The "Add more
          // photos" button / wizard navigation must therefore NOT stay
          // disabled for the background work scheduled below (durable
          // copy, HEIC preview/dimension backfill, draft snapshot, blur
          // prestage) -- see `_prepareImagesInBackground`.
          _isImportingMedia = false;
        });
        _debugLog(
          'IMMEDIATE PREVIEW: _selectedImages.length=${_selectedImages.length} '
          '(inserted with no decode/await before this setState)',
        );
        if (overLimit) _showListingMediaLimitSnack(isVideo: false);

        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
        parentState?.invalidatePhotoPrestage();
        final draftId = parentState?._currentDraftId ?? 'default';

        // Everything from here on is background-only and fire-and-forget:
        // it must never gate the gallery (already published above), the
        // "Add more photos" button, or wizard navigation -- see
        // `_prepareImagesInBackground`'s doc comment for ordering and
        // failure-behavior details.
        unawaited(
          _prepareImagesInBackground(
            newFiles,
            draftId: draftId,
            parentState: parentState,
            uiMediaIdsByPath: uiMediaIdsByPath,
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _isImportingMedia = false);
        rethrow;
      }
    } catch (e, st) {
      logNonFatal(e, st);
      _showMediaPickError(e);
    }
  }

  /// Background-only continuation of [_pickImages], run fire-and-forget
  /// (`unawaited`) right after the newly-picked photos are already visible
  /// in `_selectedImages`.
  ///
  /// Internal ordering still matters: [_backfillImageDimensions] must
  /// finish before [_syncMediaDraftToParent], which durable-copies every
  /// entry and rewrites its `source` -- see [_backfillImageDimensions]'s
  /// doc comment for why a by-path match would otherwise silently fail.
  /// None of that ordering is visible to the user, though: the gallery,
  /// the "Add more photos" button, and wizard navigation were already
  /// unblocked by `_pickImages`'s own `setState` before this was
  /// scheduled.
  ///
  /// Failure behavior: every exception here is caught and reported
  /// non-fatally. A failure here never removes or hides an
  /// already-published photo -- at worst a given item's width/height/HEIC
  /// preview backfill, its durable local copy, its draft snapshot, or its
  /// blur-prestage upload simply does not complete, and the photo keeps
  /// showing its original picker-path local preview until the user
  /// retries (e.g. by removing and re-adding it). It never silently
  /// disappears from `_selectedImages`.
  Future<void> _prepareImagesInBackground(
    List<XFile> newFiles, {
    required String draftId,
    required _SellCarPageState? parentState,
    required Map<String, String> uiMediaIdsByPath,
  }) async {
    try {
      await _backfillImageDimensions(
        newFiles,
        draftId: draftId,
        uiMediaIdsByPath: uiMediaIdsByPath,
      );
      if (!mounted) return;
      await _syncMediaDraftToParent();
      unawaited(_saveDraft());
      unawaited(parentState?.startBackgroundPlateBlur());
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Picker/permission failures are otherwise invisible, so the photo button
  /// looks dead.
  void _showMediaPickError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(
            context,
            error,
            fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
          ),
        ),
      ),
    );
  }

  Future<void> _pickDamageImages() async {
    try {
      final remaining = _kSellMaxDamagePhotos - _damageImages.length;
      if (remaining <= 0) {
        _showListingMediaLimitSnack(isDamage: true);
        return;
      }
      final files = await _imagePicker.pickMultiImage(
        maxWidth: _kSellPhotoMaxEdge,
        maxHeight: _kSellPhotoMaxEdge,
        imageQuality: _kSellPhotoQuality,
      );
      if (files.isEmpty || !mounted) return;
      final existing = _damageImages.map(_imagePathKey).toSet();
      var rawAdditions = files.where((f) => !existing.contains(f.path)).toList();
      final bool overLimit = rawAdditions.length > remaining;
      if (overLimit) {
        rawAdditions = rawAdditions.take(remaining).toList();
      }
      if (rawAdditions.isEmpty) {
        if (overLimit) _showListingMediaLimitSnack(isDamage: true);
        return;
      }
      // Same stale-media-after-delete identity tagging as `_pickImages`
      // above -- see that call site's doc comment for the full rationale.
      final uiMediaIdsByPath = <String, String>{};
      final additions = rawAdditions.map((f) {
        final id = SellMediaIdentity.stableIdFromSeed(
          'damage:${f.path}:${_uiMediaSeq++}',
        );
        uiMediaIdsByPath[f.path] = id;
        return ListingImageMedia.map(f, uiMediaId: id);
      }).toList();
      setState(() => _isImportingMedia = true);
      try {
        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
        // Insert the ORIGINAL picked damage photos into state immediately
        // -- exactly like `_pickImages` -- so the picked photo (HEIC/HEIF
        // or not) shows up without waiting on preview generation or the
        // durable copy below. `localFile()`/`previewLocalFile()` both
        // already resolve a raw `XFile` entry fine.
        setState(() {
          _damageImages = [..._damageImages, ...additions];
          // See `_pickImages`'s identical reset -- publication is already
          // complete above, so nothing below this point may keep the
          // button/navigation disabled.
          _isImportingMedia = false;
        });
        if (overLimit) _showListingMediaLimitSnack(isDamage: true);
        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
        parentState?.invalidatePhotoPrestage();
        final draftId = parentState?._currentDraftId ?? 'default';
        // Background-only from here -- see `_prepareImagesInBackground`'s
        // doc comment (same contract, reused for damage photos).
        unawaited(
          _prepareDamageImagesInBackground(
            rawAdditions,
            draftId: draftId,
            parentState: parentState,
            uiMediaIdsByPath: uiMediaIdsByPath,
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _isImportingMedia = false);
        rethrow;
      }
    } catch (e, st) {
      logNonFatal(e, st);
      _showMediaPickError(e);
    }
  }

  /// Damage-photo counterpart to [_prepareImagesInBackground] -- same
  /// ordering contract (HEIC/dimension backfill must finish before the
  /// durable-copy sync) and same failure behavior (every exception is
  /// caught and reported non-fatally; a failure never hides an
  /// already-published damage photo).
  Future<void> _prepareDamageImagesInBackground(
    List<XFile> additions, {
    required String draftId,
    required _SellCarPageState? parentState,
    required Map<String, String> uiMediaIdsByPath,
  }) async {
    try {
      await _backfillDamageImagePreviews(
        additions,
        draftId: draftId,
        uiMediaIdsByPath: uiMediaIdsByPath,
      );
      if (!mounted) return;
      await _syncMediaDraftToParent();
      unawaited(_saveDraft());
      unawaited(parentState?.startBackgroundPlateBlur());
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Real-device evidence: a 6-second `.mov` at 112,329,351 bytes was
  /// rejected by the backend's exact 100MB hard limit
  /// (`kk/routes/media.py::upload_car_videos`, unchanged by this fix --
  /// see `sell_video_compression.dart`'s file-level doc comment for the
  /// full audit). Every newly-picked video that is over that limit, or
  /// "obviously excessive" (4K/very-high-bitrate) even if it barely fits,
  /// is compressed to ~1080p/30fps H.264(+AAC) HERE -- before it is added
  /// to [_selectedVideos] and therefore before the EXISTING
  /// `_syncMediaDraftToParent()` call below durably copies it into
  /// `sell_draft_media/<draftId>/`. A video that fails to compress, or is
  /// still too large afterward, is never added -- the untouched oversized
  /// original is never submitted.
  ///
  /// Phase 3B: a source whose codec/resolution genuinely cannot be
  /// decoded on this device (`SellVideoPrepareStatus.requiresServerTranscode`,
  /// signalled by a TYPED exception -- see `sell_video_compression.dart`,
  /// never a string match) is durably staged for the server-side
  /// transcode fallback instead of being dropped -- see
  /// `_stageServerTranscodeVideo` and `sell_server_transcode_runner.dart`.
  /// It is NEVER routed through the old <=100MB multipart endpoint.
  ///
  /// ============================================================================
  /// PREVIEW-DECOUPLING FIX (real-device evidence: Samsung Galaxy A17 /
  /// Dolby Vision 4K source)
  /// ============================================================================
  /// PREVIEW and SUBMISSION-PATH RESOLUTION are deliberately two separate
  /// concerns here, exactly like the existing photo-pick pattern
  /// (`_pickImages`'s "insert original immediately, backfill
  /// width/height/HEIC-preview afterward" comment) already established
  /// for photos:
  ///   - SELECTION: every [candidate] (already deduped/within-cap) is
  ///     added to [_selectedVideos] IMMEDIATELY below -- no `await`
  ///     (probe/compress/stage) between the picker returning and that
  ///     `setState` -- so the EXISTING video-grid tile-rendering code in
  ///     `sell_step4_build_videos.dart` (thumbnail via
  ///     `generateVideoThumbnail`, tap-to-play via
  ///     `ListingPreviewGalleryPage` -> `GalleryEmbeddedVideoPlayer` ->
  ///     `VideoPlayerController.file`) shows/plays the ORIGINAL local
  ///     file right away, with zero new preview-rendering code needed.
  ///   - SUBMISSION: the loop below still runs the EXISTING duration
  ///     check + `SellVideoCompression.prepare()` for each candidate,
  ///     unchanged, and reconciles [_selectedVideos] once the outcome is
  ///     known:
  ///       * unchanged: entry already correct (same file) -- no-op.
  ///       * compressed: entry is swapped in place for the compressed
  ///         file (this IS the file that gets uploaded; the tile simply
  ///         starts reflecting the final asset once ready).
  ///       * stillTooLarge/failed/tooLong: the immediate-preview entry is
  ///         removed (same end state as before this fix -- these videos
  ///         were never added at all previously; now they briefly preview
  ///         then are removed alongside the existing error snackbar).
  ///       * requiresServerTranscode: the entry is removed from
  ///         [_selectedVideos] (it must NEVER also be uploaded via the
  ///         normal multipart path -- see `sell_listing_media_upload.dart`)
  ///         and, IN THE SAME `setState`, added to
  ///         [_pendingServerTranscodeVideos] (backed by the SAME
  ///         durably-copied original source path
  ///         `ServerTranscodeVideoSpec.localSourcePath`) -- so the tile
  ///         never visibly disappears, it just switches which backing
  ///         list renders it (task requirement 6/7: classification only
  ///         ever affects the SUBMISSION path, never hides/removes the
  ///         preview).
  /// Nothing here uploads or server-transcodes anything merely to build a
  /// preview -- `generateVideoThumbnail`/`VideoPlayerController.file` both
  /// read the local file directly, fully offline.
  Future<void> _pickVideos() async {
    // Task section 1: server contract is exactly
    // `MAX_SOURCE_DURATION_SECONDS = 30` -- was 5 minutes.
    const maxDur = Duration(seconds: 30);
    try {
      List<XFile> picked;
      try {
        picked = await _imagePicker.pickMultiVideo(maxDuration: maxDur);
      } catch (e, st) {
        logNonFatal(e, st);
        final single = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: maxDur,
        );
        picked = single != null ? <XFile>[single] : <XFile>[];
      }
      if (picked.isEmpty || !mounted) return;

      // Resolve which picked videos are new AND fit the per-listing cap
      // BEFORE compressing any of them -- compressing a video that would
      // just be dropped as a duplicate/over-cap wastes battery and time.
      //
      // Preview-decoupling fix: the cap must count BOTH `_selectedVideos`
      // AND `_pendingServerTranscodeVideos` -- a video that ends up
      // `requiresServerTranscode` is later MOVED OUT of `_selectedVideos`
      // (see the reconciliation loop below), so counting only
      // `_selectedVideos` here would silently let a seller add more than
      // `_kSellMaxVideos` total videos across multiple picks once one or
      // more videos have already migrated to the pending-transcode list.
      final existingPaths = _selectedVideos.map((e) => e.path).toSet();
      final existingTotalCount =
          _selectedVideos.length + _pendingServerTranscodeVideos.length;
      final candidates = <XFile>[];
      var overLimit = false;
      for (final v in picked) {
        if (existingPaths.contains(v.path)) continue;
        if (existingTotalCount + candidates.length >= _kSellMaxVideos) {
          overLimit = true;
          break;
        }
        candidates.add(v);
        existingPaths.add(v.path);
      }
      if (candidates.isEmpty) {
        if (overLimit) _showListingMediaLimitSnack(isVideo: true);
        return;
      }

      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';

      // PREVIEW-DECOUPLING FIX: insert every candidate's ORIGINAL local
      // file into `_selectedVideos` right now -- no `await` between the
      // picker returning (above) and this `setState` -- so the existing
      // video-grid tile (thumbnail + tap-to-play) renders it immediately,
      // completely independent of whatever the compression/server-
      // transcode classification below eventually decides. See this
      // method's file-level doc comment for the full before/after
      // reconciliation contract.
      setState(() {
        _selectedVideos.addAll(candidates);
        _isImportingMedia = true;
      });
      try {
        final prepared = <XFile>[];
        final serverTranscodeAdds = <ServerTranscodeVideoSpec>[];
        var anyStillTooLarge = false;
        var anyFailed = false;
        var anyTooLong = false;
        for (final candidate in candidates) {
          // Task section 1: reject (never silently trim) any source over
          // 30s BEFORE attempting compression or the server fallback --
          // `pickMultiVideo(maxDuration:)` above only constrains a NEW
          // camera recording, not an already-existing gallery video, so
          // this probe-based check is the actual enforcement for picks.
          final durationProbe = await SellVideoCompression.probe(candidate);
          final durationMs = durationProbe.durationMs;
          if (durationMs != null && durationMs > _kSellVideoMaxDurationMs) {
            anyTooLong = true;
            _removeSelectedVideoByPath(candidate.path);
            continue;
          }

          final result = await SellVideoCompression.prepare(
            candidate,
            onStatus: (phase) {
              if (mounted) setState(() => _videoPrepPhase = phase);
            },
          );
          switch (result.status) {
            case SellVideoPrepareStatus.unchanged:
              // Immediate-preview entry is already the correct (only)
              // file -- `result.file` is the same untouched source.
              prepared.add(result.file!);
            case SellVideoPrepareStatus.compressed:
              // Swap the immediate-preview (original) entry for the
              // COMPRESSED file that will actually be uploaded -- the
              // tile keeps showing content throughout, it just starts
              // reflecting the final asset once compression finishes.
              _replaceSelectedVideoByPath(candidate.path, result.file!);
              prepared.add(result.file!);
            case SellVideoPrepareStatus.stillTooLarge:
              anyStillTooLarge = true;
              _removeSelectedVideoByPath(candidate.path);
            case SellVideoPrepareStatus.failed:
              anyFailed = true;
              _removeSelectedVideoByPath(candidate.path);
            case SellVideoPrepareStatus.requiresServerTranscode:
              final spec = await _stageServerTranscodeVideo(
                result.file!,
                draftId: draftId,
              );
              // Move the entry from `_selectedVideos` (must NEVER also be
              // uploaded via the normal multipart path -- see
              // `sell_listing_media_upload.dart`) to
              // `_pendingServerTranscodeVideos` IN ONE `setState`, so the
              // preview tile never visibly disappears -- it only switches
              // which backing list renders it (requirement 6/7: this
              // classification affects the SUBMISSION path only).
              if (mounted) {
                setState(() {
                  _selectedVideos.removeWhere((f) => f.path == candidate.path);
                  if (spec != null) {
                    _pendingServerTranscodeVideos.add(spec);
                  }
                });
              }
              if (spec != null) {
                serverTranscodeAdds.add(spec);
              } else {
                // Durable-copy of the original itself failed -- an
                // ordinary failure, not a server-fallback candidate. The
                // immediate-preview entry was already removed above.
                anyFailed = true;
              }
          }
        }
        if (mounted) setState(() => _videoPrepPhase = null);

        if (prepared.isNotEmpty) {
          // `_selectedVideos` already holds the correct (possibly
          // in-place-replaced) entries from the loop above -- this just
          // durably copies + persists them (existing behavior, unchanged
          // shape). Existing durable-copy pipeline copies whatever is now
          // in `_selectedVideos` (the COMPRESSED file, for anything that
          // needed compressing) into `sell_draft_media/<draftId>/`,
          // awaited here exactly like every other Sell media pick, so a
          // kill right after this call still finds a durable copy on
          // disk.
          await _syncMediaDraftToParent();
          unawaited(_saveDraft());
        }
        if (serverTranscodeAdds.isNotEmpty && parentState != null) {
          final existingSpecs = ServerTranscodeVideoSpec.listFromJson(
            parentState.carData['server_transcode_videos'],
          );
          final mergedSpecs = <ServerTranscodeVideoSpec>[
            ...existingSpecs,
            ...serverTranscodeAdds,
          ];
          parentState.carData['server_transcode_videos'] =
              ServerTranscodeVideoSpec.listToJson(mergedSpecs);
          unawaited(parentState._saveSellDraftSnapshot());
        }
        if (overLimit) _showListingMediaLimitSnack(isVideo: true);
        if (anyTooLong) _showVideoTooLongSnack();
        if (anyStillTooLarge) _showVideoTooLargeSnack();
        if (anyFailed) _showVideoCompressionFailedSnack();
      } finally {
        if (mounted) {
          setState(() {
            _isImportingMedia = false;
            _videoPrepPhase = null;
          });
        }
      }
    } catch (e) {
      _showMediaPickError(e);
    }
  }

  /// Preview-decoupling fix: removes the `_selectedVideos` entry matching
  /// [path] (a no-op if it is not currently present -- e.g. already
  /// removed by a concurrent call, or duplicated logic). Used ONLY to
  /// retract an immediate-preview entry once the real classification
  /// (too long / still too large / failed / requires-server-transcode)
  /// is known -- never called for a video that is actually going to be
  /// uploaded.
  void _removeSelectedVideoByPath(String path) {
    if (!mounted) return;
    setState(() {
      _selectedVideos.removeWhere((f) => f.path == path);
    });
  }

  /// Preview-decoupling fix: swaps the `_selectedVideos` entry matching
  /// [oldPath] (the immediate-preview original) for [newFile] (the
  /// compressed output) IN PLACE, preserving grid position/order. Adds
  /// [newFile] instead if no matching entry is found (defensive -- should
  /// not normally happen, since the immediate-preview insert always runs
  /// before this).
  void _replaceSelectedVideoByPath(String oldPath, XFile newFile) {
    if (!mounted) return;
    setState(() {
      final idx = _selectedVideos.indexWhere((f) => f.path == oldPath);
      if (idx != -1) {
        _selectedVideos[idx] = newFile;
      } else {
        _selectedVideos.add(newFile);
      }
    });
  }

  /// Preview-decoupling fix: removes a not-yet-submitted pending
  /// server-transcode video preview (see
  /// [_SellStep4Fields._pendingServerTranscodeVideos]'s doc comment).
  /// Safe to do at any point before Submit -- this is purely local draft
  /// state; nothing has been signed/uploaded/finalized on the server yet
  /// for an entry the user can still see and remove at this stage (that
  /// only starts during `SellListingMediaUpload.uploadForCar` ->
  /// `SellServerTranscodeVideoRunner`, i.e. after Submit is pressed and
  /// the car already exists), so no server-side cleanup call is needed --
  /// exactly like removing a not-yet-uploaded entry from
  /// [_selectedVideos].
  void _removePendingServerTranscodeVideoAt(int index) {
    if (index < 0 || index >= _pendingServerTranscodeVideos.length) return;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    setState(() {
      _pendingServerTranscodeVideos.removeAt(index);
    });
    if (parentState != null) {
      parentState.carData['server_transcode_videos'] =
          ServerTranscodeVideoSpec.listToJson(_pendingServerTranscodeVideos);
      unawaited(parentState._saveSellDraftSnapshot());
    }
  }

  /// Phase 3B: durably copies the UNTOUCHED original [source] into
  /// `sell_draft_media/<draftId>/` (same mechanism/location every other
  /// Sell media file already uses -- namePrefix `video_src` keeps it
  /// distinguishable from a normal, already-on-device-compressed video),
  /// then builds the [ServerTranscodeVideoSpec] that
  /// `SellServerTranscodeVideoRunner` needs to sign/upload/finalize/poll/
  /// attach it later (during Submit, after the car exists -- see
  /// `sell_listing_media_upload.dart:uploadForCar`). Returns `null` (an
  /// ordinary failure, never a server-fallback candidate) only if the
  /// durable copy itself fails.
  Future<ServerTranscodeVideoSpec?> _stageServerTranscodeVideo(
    XFile source, {
    required String draftId,
  }) async {
    try {
      final persisted = await SellDraftMediaPersistence.persistDynamicMediaList(
        [source],
        draftId: draftId,
        namePrefix: 'video_src',
      );
      if (persisted.isEmpty) return null;
      final localPath = ListingImageMedia.source(persisted.first);
      if (localPath.isEmpty) return null;
      final diagnostics = await sell_video_helpers.videoUploadDiagnostics(
        source,
      );
      return ServerTranscodeVideoSpec(
        draftMediaId: _newServerTranscodeDraftMediaId(),
        localSourcePath: localPath,
        sourceByteSize: diagnostics.bytes,
        sourceMimeType: diagnostics.mime,
      );
    } catch (e, st) {
      logNonFatal(e, st);
      return null;
    }
  }

  /// Stable id satisfying the backend's `^[A-Za-z0-9_-]{1,128}$`
  /// `is_valid_draft_media_id` contract. Generated once per staged video
  /// and persisted from that point on (via `carData['server_transcode_videos']`
  /// / the eventual `SellSubmissionRecord`) -- never regenerated on retry.
  String _newServerTranscodeDraftMediaId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = math.Random().nextInt(0x7fffffff);
    return 'vst_${ts}_$rand';
  }

  void _showVideoTooLongSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.sellVideoTooLong),
      ),
    );
  }

  void _showVideoTooLargeSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.sellVideoTooLargeAfterCompression,
        ),
      ),
    );
  }

  void _showVideoCompressionFailedSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.sellVideoCompressionFailed,
        ),
      ),
    );
  }
}
