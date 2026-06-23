part of 'sell_flow.dart';
class SellStep4Page extends StatefulWidget {
  const SellStep4Page({super.key});

  @override
  State<SellStep4Page> createState() => _SellStep4PageState();
}

class _SellStep4PageState extends State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  _SellCarPageState? _parentState;
  // Can contain either local XFile (original picks) or server-relative paths (after "Blur Plates").
  List<dynamic> _selectedImages = [];
  /// Local picks and/or server-relative paths for damage / crash disclosure.
  List<dynamic> _damageImages = [];
  final List<XFile> _selectedVideos = [];
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;

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
        final raw = sp.getString(_draftKey);
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
        _draftKey,
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library, size: 48, color: Color(0xFFFF6B00)),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.addPhotos,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.addMorePhotos,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),

          // Image Processing Status
          if (_imagesProcessed)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.blur_on, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      _trLegacyText(
                        context,
                        'Images Processed',
                        ar: 'تمت معالجة الصور',
                        ku: 'وێنەکان پرۆسێس کران',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _trLegacyText(
                          context,
                          'License plates have been blurred.',
                          ar: 'تم تمويه لوحات المركبات.',
                          ku: 'ژمارەی تابلۆکان شاردراون.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Photos Section — 2 per row, full width (like home listing cards), tap to open full-screen
          Text(
            _photosRequiredTitleGlobal(context),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 12),
          if (_selectedImages.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = 8.0;
                return GridView.builder(
                  key: ValueKey(
                    _selectedImages
                        .map((e) => e is XFile ? e.path : e.toString())
                        .join('|'),
                  ),
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    final image = _selectedImages[index];
                    final keyStr = image is XFile
                        ? image.path
                        : image.toString();
                    return Stack(
                      key: ValueKey(keyStr),
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ListingPreviewGalleryPage(
                                  imageFilesOrUrls: _selectedImages,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade700),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (image is XFile)
                                ? Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    key: ValueKey(image.path),
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey.shade800,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : _listingNetworkImage(
                                    (image.toString().trim().startsWith('http'))
                                        ? image.toString().trim()
                                        : _buildFullImageUrl(image.toString()),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            unawaited(_syncMediaDraftToParent());
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.photo_library),
                  label: Text(
                    _selectedImages.isEmpty
                        ? AppLocalizations.of(context)!.addPhotos
                        : AppLocalizations.of(context)!.addMorePhotos,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _selectedImages.isNotEmpty && !_imagesProcessed
                    ? _processImages
                    : null,
                icon: _isProcessingImages
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_imagesProcessed ? Icons.check : Icons.blur_on),
                label: Text(
                  _isProcessingImages
                      ? _trLegacyText(
                          context,
                          'Processing...',
                          ar: '...جارٍ المعالجة',
                          ku: '...پرۆسێس دەکرێت',
                        )
                      : _imagesProcessed
                      ? _trLegacyText(
                          context,
                          'Processed',
                          ar: 'تمت المعالجة',
                          ku: 'پرۆسێس کرا',
                        )
                      : _trLegacyText(
                          context,
                          'Blur Plates',
                          ar: 'تمويه اللوحات',
                          ku: 'تابلۆ بشارەوە',
                        ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _imagesProcessed
                      ? Colors.green
                      : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Damage / crash photos (optional) — uploaded with kind=damage on submit
          Text(
            AppLocalizations.of(context)!.damageCrashPhotosSection,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 6),
          Text(
            _trLegacyText(
              context,
              'Shown next to title status on your listing. Not mixed into the main photo gallery.',
              ar: 'تظهر بجانب حالة الملكية في إعلانك. لا تُدمج مع معرض الصور الرئيسي.',
              ku: 'لەگەڵ دۆکی تایتڵ دەردەکەوێت، ناچێتە ناو گەلەری وێنەی سەرەکی.',
            ),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          SizedBox(height: 12),
          if (_damageImages.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                return GridView.builder(
                  key: ValueKey(
                    _damageImages
                        .map((e) => e is XFile ? e.path : e.toString())
                        .join('|'),
                  ),
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _damageImages.length,
                  itemBuilder: (context, index) {
                    final image = _damageImages[index];
                    final keyStr = image is XFile
                        ? image.path
                        : image.toString();
                    return Stack(
                      key: ValueKey('dmg_$keyStr'),
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ListingPreviewGalleryPage(
                                  imageFilesOrUrls: _damageImages,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.deepOrange.shade400,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (image is XFile)
                                ? Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    key: ValueKey(image.path),
                                  )
                                : _listingNetworkImage(
                                    (image.toString().trim().startsWith('http'))
                                        ? image.toString().trim()
                                        : _buildFullImageUrl(image.toString()),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _damageImages.removeAt(index);
                              });
                              unawaited(_syncMediaDraftToParent());
                              unawaited(_saveDraft());
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickDamageImages,
              icon: Icon(Icons.car_crash_outlined),
              label: Text(
                AppLocalizations.of(context)!
                    .addDamagePhotosCount(_damageImages.length),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade50,
                foregroundColor: Colors.deepOrange.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),

          // Videos Section — 2 per row like photos; tap opens full-screen PageView to swipe between videos
          Text(
            _videosOptionalTitleGlobal(context),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 12),
          if (_selectedVideos.isNotEmpty)
            GridView.builder(
              key: ValueKey(_selectedVideos.map((e) => e.path).join('|')),
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.25,
              ),
              itemCount: _selectedVideos.length,
              itemBuilder: (context, index) {
                final video = _selectedVideos[index];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ListingPreviewGalleryPage(
                              imageFilesOrUrls: const [],
                              videoFilesOrUrls: List<dynamic>.from(
                                _selectedVideos,
                              ),
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade700),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FutureBuilder<String?>(
                          future: generateVideoThumbnail(video.path),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(snapshot.data!),
                                    fit: BoxFit.cover,
                                  ),
                                  Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: EdgeInsets.all(16),
                                      child: Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Container(
                              color: Colors.grey[800],
                              child: Center(
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedVideos.removeAt(index);
                          });
                          unawaited(_syncMediaDraftToParent());
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickVideos,
              icon: Icon(Icons.videocam),
              label: Text(
                _selectedVideos.isEmpty
                    ? _trLegacyText(
                        context,
                        'Add Videos',
                        ar: 'إضافة فيديوهات',
                        ku: 'ڤیدیۆ زیاد بکە',
                      )
                    : _trLegacyText(
                        context,
                        'Add More Videos',
                        ar: 'إضافة المزيد من الفيديوهات',
                        ku: 'ڤیدیۆی زیاتر زیاد بکە',
                      ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 32),

          // Navigation Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                    unawaited(_syncMediaDraftToParent());
                      final parentState = context
                          .findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                        parentState._goToPreviousStep();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Color(0xFFFF6B00)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.previousButton,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF6B00),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedImages.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _pleaseSelectPhotoTextGlobal(context),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Save data and navigate to next step
                    unawaited(_syncMediaDraftToParent());
                      final parentState = context
                          .findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                      parentState.carData['images'] = List<dynamic>.from(
                        _selectedImages,
                      );
                      parentState.carData['damage_images'] =
                          List<dynamic>.from(_damageImages);
                      parentState.carData['videos'] = List<XFile>.from(
                        _selectedVideos,
                      );
                        parentState._goToNextStep();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.nextStep,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One slot in the review-step media carousel (photo or video).
