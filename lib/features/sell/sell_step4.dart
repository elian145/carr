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
class _PreviewMediaEntry {
  const _PreviewMediaEntry({required this.isVideo, required this.item});
  final bool isVideo;
  final dynamic item;
}

// Preview of how the listing will look after submission (used in SellStep5).
class ListingPreviewWidget extends StatefulWidget {
  final Map<String, dynamic> carData;
  final List<dynamic> imageFilesOrUrls;

  /// When true, renders edge-to-edge like the real listing page (no rounded corners/border).
  final bool fullPage;

  const ListingPreviewWidget({
    super.key,
    required this.carData,
    required this.imageFilesOrUrls,
    this.fullPage = false,
  });

  @override
  State<ListingPreviewWidget> createState() => _ListingPreviewWidgetState();
}

class _ListingPreviewWidgetState extends State<ListingPreviewWidget> {
  final PageController _imagePageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = item is XFile ? item.path : item.toString().trim();
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  static String? _getFirstNonEmpty(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String _formatPrice(BuildContext context, String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      final formatter = _decimalFormatterGlobal(context);
      return formatter.format(value);
    } catch (e, st) { logNonFatal(e, st); 
      return raw;
    }
  }

  Widget _buildSpecCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: BoxConstraints(minHeight: 84),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.icon, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Flexible(
                child: AutoSizeText(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textScaleFactor: 1.0,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                  minFontSize: 7,
                  stepGranularity: 0.5,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withValues(alpha: 0.22),
            ),
          ),
          AutoSizeText(
            item.value!,
            maxLines: 2,
            textAlign: TextAlign.center,
            textScaleFactor: 1.0,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF3F3F3)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFE0E0E0) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsFromData(Map<String, dynamic> data) {
    final loc = AppLocalizations.of(context)!;
    final String? engineSize = _getFirstNonEmpty(data, [
      'engine_size',
      'engineSize',
      'engine',
    ]);
    final List<_SpecItem> primary = [
      _SpecItem(
        icon: Icons.speed,
        label: loc.mileageLabel,
        value: data['mileage'] != null
            ? '${_localizeDigitsGlobal(context, _formatPrice(context, data['mileage'].toString()))} ${loc.unit_km}'
            : null,
      ),
      _SpecItem(
        icon: Icons.settings_input_component,
        label: loc.detail_cylinders,
        value: () {
          final raw = _getFirstNonEmpty(data, [
            'cylinder_count',
            'cylinders',
            'cylinderCount',
          ]);
          if (raw == null) return null;
          return _localizeDigitsGlobal(context, raw);
        }(),
      ),
      _SpecItem(
        icon: Icons.straighten,
        label: loc.detail_engine,
        value: engineSize != null
            ? '${_localizeDigitsGlobal(context, engineSize.toString())}${loc.unit_liter_suffix}'
            : null,
      ),
      _SpecItem(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _SpecItem(
        icon: Icons.settings,
        label: loc.transmissionLabel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['transmission']),
        ),
      ),
      _SpecItem(
        icon: Icons.local_gas_station,
        label: loc.detail_fuel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['fuel_type']),
        ),
      ),
    ];
    final List<Widget> details = [
      _detailRow(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _detailRow(
        icon: Icons.check_circle,
        label: loc.detail_condition,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['condition']),
        ),
      ),
      _detailRow(
        icon: Icons.assignment_turned_in,
        label: loc.titleStatus,
        value: data['title_status'] != null
            ? (data['title_status'].toString().toLowerCase() == 'damaged'
                  ? (data['damaged_parts'] != null
                        ? loc.titleStatusDamagedWithParts(
                            _localizeDigitsGlobal(
                              context,
                              data['damaged_parts'].toString(),
                            ),
                          )
                        : loc.value_title_damaged)
                  : loc.value_title_clean)
            : null,
      ),
      _detailRow(
        icon: Icons.drive_eta,
        label: loc.detail_drive,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, [
            'drive_type',
            'driveType',
            'drivetrain',
            'drive',
          ]),
        ),
      ),
      _detailRow(
        icon: Icons.directions_car_filled,
        label: loc.detail_body,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['body_type', 'bodyType', 'body']),
        ),
      ),
      _detailRow(
        icon: Icons.color_lens,
        label: loc.detail_color,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['color']),
        ),
      ),
      _detailRow(
        icon: Icons.airline_seat_recline_normal,
        label: loc.detail_seating,
        value: _localizeDigitsGlobal(
          context,
          _getFirstNonEmpty(data, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
      _detailRow(
        icon: Icons.phone,
        label: loc.phoneLabel,
        value: _getFirstNonEmpty(data, ['contact_phone']),
      ),
      _detailRow(
        icon: Icons.pin_outlined,
        label: 'VIN',
        value: _getFirstNonEmpty(data, ['vin']),
      ),
    ];
    final primItems = primary
        .where((i) => i.value != null && i.value!.isNotEmpty)
        .toList();
    final primGrid = GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: primItems.length,
      itemBuilder: (context, index) => _buildSpecCard(primItems[index]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [primGrid, SizedBox(height: 12), ...details],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.carData;
    final images = widget.imageFilesOrUrls;
    final dynamic rawVideos = data['videos'];
    final List<dynamic> videos = rawVideos is List ? rawVideos : const [];
    final List<_PreviewMediaEntry> media = [
      ...images.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...videos.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
    final hasMedia = media.isNotEmpty;

    final String title = (data['title']?.toString() ?? '').trim().isNotEmpty
        ? data['title'].toString().trim()
        : '${data['brand'] ?? ''} ${data['model'] ?? ''} ${data['trim'] ?? ''}'
              .trim();
    final String yearStr = data['year'] != null ? data['year'].toString() : '';
    final String titleWithYear = yearStr.isNotEmpty
        ? '$title ($yearStr)'
        : (title.isEmpty ? 'Your listing' : title);

    final bool fullPage = widget.fullPage;
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: fullPage ? BorderRadius.zero : BorderRadius.circular(16),
        border: fullPage ? null : Border.all(color: Colors.grey[700]!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo + video carousel — tap: images open gallery, videos open preview/player
          SizedBox(
            height: fullPage ? 300 : 260,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasMedia)
                  GestureDetector(
                    onTap: () => _openCarouselDetail(context, media, images),
                    child: PageView.builder(
                      controller: _imagePageController,
                      onPageChanged: (idx) =>
                          setState(() => _currentMediaIndex = idx),
                      itemCount: media.length,
                      itemBuilder: (context, index) {
                        final slot = media[index];
                        if (slot.isVideo) {
                          return _buildVideoCarouselSlide(slot.item);
                        }
                        final item = slot.item;
                        if (item is XFile) {
                          return Image.file(
                            File(item.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        }
                        final url = item.toString().trim();
                        final fullUrl = url.startsWith('http')
                            ? url
                            : _buildFullImageUrl(url);
                        return _listingNetworkImage(
                          fullUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        );
                      },
                    ),
                  )
                else
                  Container(
                    color: Colors.grey[800],
                    child: Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Colors.grey[500],
                    ),
                  ),
                if (hasMedia && media.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(media.length, (i) {
                          final active = i == _currentMediaIndex;
                          return AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            margin: EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 10 : 6,
                            height: active ? 10 : 6,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Content (title, price, specs)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['is_quick_sell'] == true ||
                    data['is_quick_sell'] == 'true')
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange, Colors.deepOrange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flash_on, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.quickSell,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  titleWithYear,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                if (data['price'] != null &&
                    data['price'].toString().trim().isNotEmpty)
                  Text(
                    _formatCurrencyGlobal(context, data['price']),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                SizedBox(height: 16),
                Divider(height: 1, thickness: 1, color: Colors.white24),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.specificationsLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                ),
                SizedBox(height: 12),
                _buildSpecsFromData(data),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sellReviewListingBrand(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final locBrand = CarNameTranslations.getLocalizedBrand(
    context,
    brand.isEmpty ? null : brand,
  );
  if (locBrand.isNotEmpty) return locBrand;
  return (car['title'] ?? '').toString().trim();
}

String _sellReviewListingModel(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  final localizedModel = CarNameTranslations.getLocalizedModel(
    context,
    brand.isEmpty ? null : brand,
    model.isEmpty ? null : model,
  );
  final displayModel = localizedModel.isNotEmpty ? localizedModel : model;
  final year = (car['year'] ?? '').toString().trim();
  if (displayModel.isEmpty) return year;
  if (year.isEmpty) return displayModel;
  return '$displayModel $year';
}

bool _sellReviewHasPrice(Map<String, dynamic> car) {
  final p = car['price'];
  if (p == null) return false;
  return p.toString().trim().isNotEmpty;
}

/// Sell step 5 preview: matches [CarDetailsPage] layout and light/dark theming.
class SellReviewCarDetailScrollView extends StatefulWidget {
  const SellReviewCarDetailScrollView({super.key, required this.carData});

  final Map<String, dynamic> carData;

  @override
  State<SellReviewCarDetailScrollView> createState() =>
      _SellReviewCarDetailScrollViewState();
}

class _SellReviewCarDetailScrollViewState
    extends State<SellReviewCarDetailScrollView> {
  final PageController _pageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_PreviewMediaEntry> _buildMediaList() {
    final imgs = widget.carData['images'];
    final vids = widget.carData['videos'];
    final il = imgs is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(imgs),
          )
        : const <dynamic>[];
    final vl = vids is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(vids),
          )
        : const <dynamic>[];
    return [
      ...il.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...vl.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
  }

  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = item is XFile ? item.path : item.toString().trim();
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final car = widget.carData;
    final media = _buildMediaList();
    final brandStr = _sellReviewListingBrand(context, car);
    final modelStr = _sellReviewListingModel(context, car);
    final rawImages = car['images'] is List ? (car['images'] as List) : [];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (media.isEmpty)
                    Container(
                      color: Colors.grey[900],
                      child: Icon(
                        Icons.directions_car,
                        size: 60,
                        color: Colors.grey[400],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () =>
                          _openCarouselDetail(context, media, rawImages),
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (idx) =>
                            setState(() => _currentMediaIndex = idx),
                        itemCount: media.length,
                        itemBuilder: (context, index) {
                          final slot = media[index];
                          if (slot.isVideo) {
                            return _buildVideoCarouselSlide(slot.item);
                          }
                          final item = slot.item;
                          if (item is XFile) {
                            return Image.file(
                              File(item.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey[900],
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                              ),
                            );
                          }
                          final url = item.toString().trim();
                          final fullUrl = url.startsWith('http')
                              ? url
                              : _buildFullImageUrl(url);
                          return _listingNetworkImage(
                            fullUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        },
                      ),
                    ),
                  if (media.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(media.length, (i) {
                                final active = i == _currentMediaIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: active ? 10 : 6,
                                  height: active ? 10 : 6,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white
                                        : Colors.white70,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isLightShell
                  ? AppThemes.lightAppBackground
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Theme(
              data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (car['is_quick_sell'] == true ||
                      car['is_quick_sell'] == 'true')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.flash_on,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.quickSell,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              brandStr,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_sellReviewHasPrice(car) && modelStr.isEmpty) ...[
                            const SizedBox(width: 12),
                            Text(
                              _formatCurrencyGlobal(context, car['price']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (modelStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                modelStr,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isLightShell
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_sellReviewHasPrice(car)) ...[
                              const SizedBox(width: 12),
                              Text(
                                _formatCurrencyGlobal(context, car['price']),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6B00),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                  // Match Home listing card: city / uploaded info goes below title + price.
                  Builder(
                    builder: (context) {
                      String? pickCity(List<String> keys) {
                        for (final k in keys) {
                          final v = car[k]?.toString().trim();
                          if (v != null && v.isNotEmpty) return v;
                        }
                        return null;
                      }

                      final cityDetail = (pickCity(['city', 'location']) ?? '')
                          .trim();
                      final uploadedDetail = _listingUploadedAgo(context, car);
                      if (cityDetail.isEmpty && uploadedDetail.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final cityLabelStyle = TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isLightShell
                            ? const Color(0xFF757575)
                            : Colors.white70,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: cityDetail.isEmpty
                                  ? const SizedBox.shrink()
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_city,
                                          size: 14,
                                          color: isLightShell
                                              ? const Color(0xFF757575)
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${AppLocalizations.of(context)!.cityLabel}: ${_translateValueGlobal(context, pickCity(['city', 'location'])) ?? pickCity(['city', 'location'])}',
                                            style: cityLabelStyle,
                                            // Allow long cities like "Sulaymaniyah" to show fully.
                                            maxLines: 2,
                                            overflow: TextOverflow.clip,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            if (uploadedDetail.isNotEmpty) ...[
                              if (cityDetail.isNotEmpty)
                                const SizedBox(width: 8),
                              Text(
                                uploadedDetail,
                                style: cityLabelStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isLightShell
                        ? const Color(0xFFE0E0E0)
                        : Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.specificationsLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                  const SizedBox(height: 20),
                  buildCarListingSpecsGrid(context, car),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Step 5: Review & Submit
