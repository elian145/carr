part of 'sell_flow.dart';

/// Client-side media caps for a single listing (the backend also enforces limits).
const int _kSellMaxPhotos = 20;
const int _kSellMaxVideos = 3;
const int _kSellMaxDamagePhotos = 10;

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
    if (!mounted) return;
    if (_selectedImages.isNotEmpty ||
        _damageImages.isNotEmpty ||
        _selectedVideos.isNotEmpty) {
      await _syncMediaDraftToParent();
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
      if (mounted) {
        setState(() {
          _selectedImages = images;
          _blurredImages = blurred;
          _damageImages = damage;
          _selectedVideos
            ..clear()
            ..addAll(ListingImageMedia.localFiles(videos));
        });
      }
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await sp.setString(
        _SellStep4Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedImages': images
              .map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : ListingImageMedia.map(e),
              )
              .toList(),
          'blurredImages': blurred
              .map(
                (e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : ListingImageMedia.map(e),
              )
              .toList(),
          'damage_images': damage.map(ListingImageMedia.source).toList(),
          'selectedVideos': videos.map(ListingImageMedia.source).toList(),
          'imagesProcessed': _imagesProcessed,
          'primaryImageIndex': _primaryImageIndex,
        }),
      );
      if (parentState != null) {
        _writeMediaListsToParent(
          parentState,
          images: images,
          blurred: blurred,
          damage: damage,
          videos: ListingImageMedia.localFiles(videos),
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
    if (!mounted) return;
    setState(() {
      _selectedImages = images;
      _blurredImages = blurred;
      _damageImages = damage;
      _selectedVideos
        ..clear()
        ..addAll(ListingImageMedia.localFiles(videos));
    });
    _writeMediaListsToParent(
      parentState,
      images: images,
      blurred: blurred,
      damage: damage,
      videos: ListingImageMedia.localFiles(videos),
    );
    if (_imagesProcessed && blurred.isNotEmpty) {
      parentState.carData['processed_image_paths'] = blurred
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

  Future<Map<String, dynamic>> _pickedImageMedia(XFile file) async {
    int? width;
    int? height;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (e, st) {
      logNonFatal(e, st);
    }
    return ListingImageMedia.map(file, width: width, height: height);
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
        final additions = await Future.wait(newFiles.map(_pickedImageMedia));
        if (!mounted || additions.isEmpty) return;
        final parentState = context.findAncestorStateOfType<_SellCarPageState>();
        setState(() {
          _selectedImages = [..._selectedImages, ...additions];
          _imagesProcessed = false;
          _blurredImages = [];
          _isProcessingImages = false;
        });
        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
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
        setState(() {
          _damageImages = [..._damageImages, ...additions];
        });
        parentState?.carData.remove('use_blurred_plates');
        parentState?.invalidatePlateBlurJob();
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

  Future<void> _pickVideos() async {
    const maxDur = Duration(minutes: 5);
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
      setState(() => _isImportingMedia = true);
      try {
        bool overLimit = false;
        setState(() {
          final existing = _selectedVideos.map((e) => e.path).toSet();
          for (final v in picked) {
            if (existing.contains(v.path)) continue;
            if (_selectedVideos.length >= _kSellMaxVideos) {
              overLimit = true;
              break;
            }
            _selectedVideos.add(v);
            existing.add(v.path);
          }
        });
        await _syncMediaDraftToParent();
        unawaited(_saveDraft());
        if (overLimit) _showListingMediaLimitSnack(isVideo: true);
      } finally {
        if (mounted) setState(() => _isImportingMedia = false);
      }
    } catch (e) {
      _showMediaPickError(e);
    }
  }
}
