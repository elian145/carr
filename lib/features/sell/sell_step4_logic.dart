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
          _clampPrimaryImageIndex();
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData['original_images'] =
            List<dynamic>.from(mergedImages);
        parentState.carData['blurred_images'] =
            List<dynamic>.from(mergedBlurred);
        parentState.carData['images'] = List<dynamic>.from(mergedImages);
        parentState.carData['original_damage_images'] =
            List<dynamic>.from(mergedDamage);
        if (parentDamageBlurred is List) {
          parentState.carData['blurred_damage_images'] =
              List<dynamic>.from(parentDamageBlurred);
        }
        parentState.carData['damage_images'] =
            List<dynamic>.from(mergedDamage);
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
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    final draftId = parentState._currentDraftId;
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
    final resolvedImages = _persistedOrLiveMedia(_selectedImages, images);
    final resolvedBlurred = _persistedOrLiveMedia(_blurredImages, blurred);
    final resolvedDamage = _persistedOrLiveMedia(_damageImages, damage);
    final resolvedVideos = _persistedOrLiveMedia(
      _selectedVideos.map((f) => f.path).toList(),
      videos,
    );
    if (!mounted) return;
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
      parentState.carData['blurred_images'] = List<dynamic>.from(blurred);
      parentState.carData['images_processed'] = true;
      _imagesProcessed = true;
      _blurredImages = List<dynamic>.from(blurred);
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
    );
  }

  /// Decodes width/height (and, for HEIC/HEIF, generates a local JPEG
  /// preview -- see `HeicPreviewConverter`) for freshly-picked photos and
  /// backfills them onto the matching `_selectedImages` entry (matched by
  /// path, so it stays correct even if the user removes/reorders photos
  /// while this is still running -- see A-fix item 9, "removing/reordering
  /// images keeps mappings correct"). Never blocks or delays the original's
  /// first render -- that already happened in `_pickImages`'s first
  /// `setState`, before this is ever called.
  ///
  /// Must run, and be awaited, BEFORE `_syncMediaDraftToParent()`: that
  /// durable-copies each file, which *rewrites* `ListingImageMedia.source`
  /// to a new `sell_draft_media/...` path -- if this ran afterward (as it
  /// used to, unawaited), the by-path match below would already always
  /// fail to find the (renamed) entry, silently dropping the backfill.
  Future<void> _backfillImageDimensions(
    List<XFile> files, {
    required String draftId,
  }) async {
    for (final file in files) {
      if (!mounted) return;
      final enriched = await _pickedImageMedia(file, draftId: draftId);
      if (!mounted) return;
      final idx = _selectedImages.indexWhere(
        (item) => ListingImageMedia.source(item) == file.path,
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
      setState(() => _selectedImages[idx] = enriched);
    }
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
  }) async {
    for (final file in files) {
      if (!mounted) return;
      final enriched = await _pickedImageMedia(
        file,
        draftId: draftId,
        logContext: '[DAMAGE]',
      );
      if (!mounted) return;
      final idx = _damageImages.indexWhere(
        (item) => ListingImageMedia.source(item) == file.path,
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
      if (index < _blurredImages.length) {
        _blurredImages.removeAt(index);
      } else {
        _blurredImages = [];
        _imagesProcessed = false;
      }
      _onImageRemovedAt(index);
      if (_selectedImages.isEmpty) {
        _blurredImages = [];
        _imagesProcessed = false;
      }
    });
    parentState?.carData.remove('use_blurred_plates');
    parentState?.invalidatePlateBlurJob();
    parentState?.invalidatePhotoPrestage();
    unawaited(_syncMediaDraftToParent());
    if (_selectedImages.isNotEmpty) {
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
        final additions = newFiles.map(ListingImageMedia.map).toList();
        if (!mounted || additions.isEmpty) return;
        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
        setState(() {
          _selectedImages = [..._selectedImages, ...additions];
          _imagesProcessed = false;
          _blurredImages = [];
          _isProcessingImages = false;
        });
        _debugLog(
          'IMMEDIATE PREVIEW: _selectedImages.length=${_selectedImages.length} '
          '(inserted with no decode/await before this setState)',
        );
        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
        parentState?.invalidatePhotoPrestage();
        // Width/height + HEIC/HEIF preview backfill must run (and finish)
        // BEFORE the durable-copy step below, which rewrites each entry's
        // `source` -- see `_backfillImageDimensions`'s doc comment. The
        // original is already visible from the setState above; this only
        // delays the durable copy/background blur trigger, never the
        // original's first render.
        final draftId = parentState?._currentDraftId ?? 'default';
        await _backfillImageDimensions(newFiles, draftId: draftId);
        if (!mounted) return;
        await _syncMediaDraftToParent();
        unawaited(_saveDraft());
        unawaited(parentState?.startBackgroundPlateBlur());
        if (overLimit) _showListingMediaLimitSnack(isVideo: false);
      } finally {
        if (mounted) setState(() => _isImportingMedia = false);
      }
    } catch (e, st) {
      logNonFatal(e, st);
      _showMediaPickError(e);
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
      var additions = files.where((f) => !existing.contains(f.path)).toList();
      final bool overLimit = additions.length > remaining;
      if (overLimit) {
        additions = additions.take(remaining).toList();
      }
      if (additions.isEmpty) {
        if (overLimit) _showListingMediaLimitSnack(isDamage: true);
        return;
      }
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
        });
        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
        parentState?.invalidatePhotoPrestage();
        // HEIC/HEIF preview fix (damage photos): must run, and be
        // awaited, BEFORE `_syncMediaDraftToParent()` below -- see
        // `_backfillDamageImagePreviews`'s doc comment for why order
        // matters here (same durable-copy path-rewrite hazard already
        // fixed for listing photos).
        final draftId = parentState?._currentDraftId ?? 'default';
        await _backfillDamageImagePreviews(additions, draftId: draftId);
        if (!mounted) return;
        await _syncMediaDraftToParent();
        unawaited(_saveDraft());
        unawaited(parentState?.startBackgroundPlateBlur());
        if (overLimit) _showListingMediaLimitSnack(isDamage: true);
      } finally {
        if (mounted) setState(() => _isImportingMedia = false);
      }
    } catch (e, st) {
      logNonFatal(e, st);
      _showMediaPickError(e);
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
      final existingPaths = _selectedVideos.map((e) => e.path).toSet();
      final candidates = <XFile>[];
      var overLimit = false;
      for (final v in picked) {
        if (existingPaths.contains(v.path)) continue;
        if (_selectedVideos.length + candidates.length >= _kSellMaxVideos) {
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

      setState(() => _isImportingMedia = true);
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
            case SellVideoPrepareStatus.compressed:
              prepared.add(result.file!);
            case SellVideoPrepareStatus.stillTooLarge:
              anyStillTooLarge = true;
            case SellVideoPrepareStatus.failed:
              anyFailed = true;
            case SellVideoPrepareStatus.requiresServerTranscode:
              final spec = await _stageServerTranscodeVideo(
                result.file!,
                draftId: draftId,
              );
              if (spec != null) {
                serverTranscodeAdds.add(spec);
              } else {
                // Durable-copy of the original itself failed -- an
                // ordinary failure, not a server-fallback candidate.
                anyFailed = true;
              }
          }
        }
        if (mounted) setState(() => _videoPrepPhase = null);

        if (prepared.isNotEmpty) {
          setState(() {
            _selectedVideos.addAll(prepared);
          });
          // Existing durable-copy pipeline (unchanged) -- copies whatever
          // is now in `_selectedVideos` (the COMPRESSED file, for anything
          // that needed compressing) into
          // `sell_draft_media/<draftId>/`, awaited here exactly like every
          // other Sell media pick, so a kill right after this call still
          // finds a durable copy on disk.
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
