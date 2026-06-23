part of 'sell_flow.dart';

mixin _SellStep4Build on _SellStep4Body {
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
