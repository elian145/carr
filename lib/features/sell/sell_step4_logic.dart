part of 'sell_flow.dart';

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
          _damageImages = [];
          _selectedVideos.clear();
          _imagesProcessed = false;
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData.remove('images');
        parentState.carData.remove('damage_images');
        parentState.carData.remove('videos');
        parentState.carData.remove('images_processed');
        parentState.carData.remove('processed_image_paths');
      }
    } else {
      final parentImages = parentState?.carData['images'];
      final parentDamage = parentState?.carData['damage_images'];
      final parentVideos = parentState?.carData['videos'];
      List<dynamic> stepImages = const [];
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
            if (data['damage_images'] is List) {
              stepDamage = List<dynamic>.from(data['damage_images'] as List);
            }
            if (data['selectedVideos'] is List) {
              stepVideos = (data['selectedVideos'] as List)
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty && File(e).existsSync())
                  .map((e) => XFile(e))
                  .toList();
            }
            _imagesProcessed = data['imagesProcessed'] == true;
          }
        }
      } catch (e, st) { logNonFatal(e, st); }

      final mergedImages = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentImages is List ? List<dynamic>.from(parentImages) : null,
        secondary: stepImages,
      );
      final mergedDamage = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentDamage is List ? List<dynamic>.from(parentDamage) : null,
        secondary: stepDamage,
      );
      final mergedVideos = SellDraftMediaPersistence.coalesceMediaLists(
        primary: parentVideos is List ? List<dynamic>.from(parentVideos) : null,
        secondary: stepVideos.map((e) => e.path).toList(),
      );

      if (mounted) {
        setState(() {
          _selectedImages = mergedImages;
          _damageImages = mergedDamage;
          _selectedVideos
            ..clear()
            ..addAll(mergedVideos.whereType<XFile>());
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(mergedImages);
        parentState.carData['damage_images'] =
            List<dynamic>.from(mergedDamage);
        parentState.carData['videos'] = List<XFile>.from(
          mergedVideos.whereType<XFile>(),
        );
        parentState.carData['images_processed'] = _imagesProcessed;
      }
    }
    if (!mounted) return;
    if (_selectedImages.isNotEmpty ||
        _damageImages.isNotEmpty ||
        _selectedVideos.isNotEmpty) {
      await _syncMediaDraftToParent();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentState ??= context.findAncestorStateOfType<_SellCarPageState>();
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      final parentState = _parentState;
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(_selectedImages);
        parentState.carData['damage_images'] =
            List<dynamic>.from(_damageImages);
        parentState.carData['videos'] = List<XFile>.from(_selectedVideos);
        parentState.carData['images_processed'] = _imagesProcessed;
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
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';
      final images = await SellDraftMediaPersistence.persistDynamicMediaList(
        _selectedImages,
        draftId: draftId,
        namePrefix: 'listing',
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
      if (mounted) {
        setState(() {
          _selectedImages = images;
          _damageImages = damage;
          _selectedVideos
            ..clear()
            ..addAll(videos.whereType<XFile>());
        });
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _SellStep4Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedImages': images
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'damage_images': damage
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'selectedVideos': videos
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'imagesProcessed': _imagesProcessed,
        }),
      );
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(images);
        parentState.carData['damage_images'] = List<dynamic>.from(damage);
        parentState.carData['videos'] = List<XFile>.from(
          videos.whereType<XFile>(),
        );
        parentState.carData['images_processed'] = _imagesProcessed;
      }
      unawaited(parentState?._saveSellDraftSnapshot());
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _syncMediaDraftToParent() async {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    final draftId = parentState._currentDraftId;
    final images = await SellDraftMediaPersistence.persistDynamicMediaList(
      _selectedImages,
      draftId: draftId,
      namePrefix: 'listing',
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
      _damageImages = damage;
      _selectedVideos
        ..clear()
        ..addAll(videos.whereType<XFile>());
    });
    parentState.carData['images'] = List<dynamic>.from(images);
    parentState.carData['damage_images'] = List<dynamic>.from(damage);
    parentState.carData['videos'] = List<XFile>.from(
      videos.whereType<XFile>(),
    );
    parentState.carData['images_processed'] = _imagesProcessed;
    if (_imagesProcessed) {
      parentState.carData['processed_image_paths'] = images
          .map((e) => e is XFile ? e.path : e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } else {
      parentState.carData.remove('processed_image_paths');
    }
    parentState.setState(() {});
    unawaited(parentState._saveSellDraftSnapshot());
  }

  String _imagePathKey(dynamic item) =>
      item is XFile ? item.path : item.toString().trim();

  Future<void> _pickImages() async {
    try {
      // Upload full-resolution images to improve YOLO/OCR accuracy
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      final existing = _selectedImages.map(_imagePathKey).toSet();
      final additions = files.where((f) => !existing.contains(f.path)).toList();
      if (additions.isEmpty) return;
      setState(() {
        _selectedImages = [..._selectedImages, ...additions];
        _imagesProcessed = false;
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _pickDamageImages() async {
    try {
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      final existing = _damageImages.map(_imagePathKey).toSet();
      final additions = files.where((f) => !existing.contains(f.path)).toList();
      if (additions.isEmpty) return;
      setState(() {
        _damageImages = [..._damageImages, ...additions];
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _processImages() async {
    if (_selectedImages.isEmpty) {
      _debugLog('AI UI: No images selected for processing');
      return;
    }

    if (!await ensurePhoneVerifiedForAction(context)) {
      return;
    }

    _debugLog(
      'AI UI: Starting image processing for ${_selectedImages.length} images',
    );

    if (!mounted) return;
    setState(() {
      _isProcessingImages = true;
    });

    try {
      // Blur only when user taps "Blur Plates": process/store images on the server
      // and replace the local picks with server paths for preview + later attach.
      final local = _selectedImages.whereType<XFile>().toList();
      if (local.isEmpty) {
        if (!mounted) return;
        setState(() {
          _imagesProcessed = true;
        });
        return;
      }

      _debugLog('AI UI: Calling AiService.processCarImagesToServerPayload...');
      final payload = await AiService.processCarImagesToServerPayload(local);
      final paths = payload?['paths'] ?? const <String>[];
      final b64 = payload?['base64'] ?? const <String>[];

      if (paths.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to blur plates. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Build local preview files from base64 (avoids loading many /static/ URLs concurrently, which can drop connections)
      final List<XFile> blurredLocal = <XFile>[];
      final List<String> okPaths = <String>[];
      if (!mounted) return;
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';
      try {
        final int n = paths.length;
        for (int i = 0; i < n; i++) {
          final String path = paths[i].toString();
          final String? dataUri = (i < b64.length) ? b64[i].toString() : null;
          if (dataUri != null &&
              dataUri.startsWith('data:') &&
              dataUri.contains('base64,')) {
            final idx = dataUri.indexOf('base64,');
            final raw = base64Decode(dataUri.substring(idx + 7));
            final stored = await SellDraftMediaPersistence.persistBytesToDraft(
              raw,
              draftId: draftId,
              namePrefix: 'listing_blur',
            );
            if (stored != null && stored.isNotEmpty) {
              blurredLocal.add(XFile(stored));
              okPaths.add(path);
            }
          } else if (i < local.length) {
            blurredLocal.add(local[i]);
          }
        }
      } catch (e) {
        _debugLog('AI UI: Failed to build local previews from base64: $e');
      }

      if (!mounted) return;
      setState(() {
        _selectedImages = blurredLocal.isNotEmpty
            ? blurredLocal
            : List<String>.from(paths);
        _imagesProcessed = true;
      });

      unawaited(_syncMediaDraftToParent());
      if (parentState != null) {
        parentState.carData['processed_image_paths'] = List<String>.from(
          okPaths.isNotEmpty ? okPaths : paths,
        );
        parentState.setState(() {});
        unawaited(parentState._saveSellDraftSnapshot());
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Plates blurred successfully.')));
    } catch (e) {
      _debugLog('AI UI: Error processing images: $e');
      if (!mounted) return;
      if (isPhoneVerificationRequired(e)) {
        await ensurePhoneVerifiedForAction(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: 'Failed to blur plates. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImages = false;
        });
      }
    }
  }

  Future<void> _pickVideos() async {
    const maxDur = Duration(minutes: 5);
    try {
      List<XFile> picked;
      try {
        picked = await _imagePicker.pickMultiVideo(maxDuration: maxDur);
      } catch (e, st) { logNonFatal(e, st); 
        // Some platforms/plugins may not support multi-video selection.
        final single = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: maxDur,
        );
        picked = single != null ? <XFile>[single] : <XFile>[];
      }
      if (picked.isEmpty || !mounted) return;
      setState(() {
        final existing = _selectedVideos.map((e) => e.path).toSet();
        for (final v in picked) {
          if (!existing.contains(v.path)) {
            _selectedVideos.add(v);
            existing.add(v.path);
          }
        }
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video selection failed: $e')));
    }
  }

}
