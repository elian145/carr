part of 'sell_flow.dart';

mixin _SellStep4BuildPhotos on _SellStep4BuildIntro {
  List<Widget> _sellStep4BuildPhotosSection() {
    final loc = AppLocalizations.of(context)!;
    final hasPhotos = _selectedImages.isNotEmpty;
    final countLabel = hasPhotos
        ? loc.addPhotosCount(_selectedImages.length)
        : loc.tapToSelect;
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final blurring = parent?.isBlurringPlates == true;
    final blurReady = parent?.hasBlurredPlatesReady == true ||
        (_imagesProcessed && _blurredImages.isNotEmpty);

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: _trLegacyText(
                context,
                'Photos',
                ar: 'الصور',
                ku: 'وێنەکان',
              ),
              requiredField: true,
              valueSummary: countLabel,
            ),
            if (_selectedImages.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                _trLegacyText(
                  context,
                  'Tap the star on a photo to set it as the cover image shown first in your listing.',
                  ar: 'اضغط على النجمة على الصورة لتعيينها كصورة الغلاف التي تظهر أولاً في إعلانك.',
                  ku: 'کرتە بکە لە ئەستێرەکە لەسەر وێنەکە بۆ ئەوەی وەک وێنەی سەرەکی یەکەم لە ڕیکلامەکەتدا دەربکەوێت.',
                ),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (hasPhotos)
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  return GridView.builder(
                    key: ValueKey(
                      _selectedImages.map(ListingImageMedia.source).join('|'),
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: 1.25,
                    ),
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      final image = _selectedImages[index];
                      final keyStr = ListingImageMedia.source(image);
                      final localFile = ListingImageMedia.localFile(image);
                      final isPrimary = index == 0;
                      return Stack(
                        key: ValueKey(keyStr),
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => ListingPreviewGalleryPage(
                                    imageFilesOrUrls:
                                        _selectedImages.map((item) {
                                      final local =
                                          ListingImageMedia.localFile(item);
                                      return local ??
                                          ListingImageMedia.source(item);
                                    }).toList(),
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isPrimary
                                      ? kFilterAccentColor
                                      : Colors.grey.shade300,
                                  width: isPrimary ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: localFile != null
                                  ? Image.file(
                                      File(localFile.path),
                                      fit: BoxFit.cover,
                                      alignment:
                                          ListingImageMedia.coverAlignment(
                                        image,
                                      ),
                                      width: double.infinity,
                                      height: double.infinity,
                                      key: ValueKey(localFile.path),
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                        color: Colors.grey.shade200,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.grey.shade500,
                                          size: 32,
                                        ),
                                      ),
                                    )
                                  : _listingNetworkImage(
                                      keyStr.startsWith('http')
                                          ? keyStr
                                          : _buildFullImageUrl(keyStr),
                                      fit: BoxFit.cover,
                                      alignment:
                                          ListingImageMedia.coverAlignment(
                                        image,
                                      ),
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                            ),
                          ),
                          if (isPrimary)
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: kFilterAccentColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _trLegacyText(
                                        context,
                                        'Cover',
                                        ar: 'الغلاف',
                                        ku: 'سەرەکی',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: InkWell(
                                onTap: () => _setPrimaryImage(index),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: const Icon(
                                    Icons.star_border,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: InkWell(
                        onTap: () {
                          final parentState = context
                              .findAncestorStateOfType<_SellCarPageState>();
                          setState(() {
                            _selectedImages.removeAt(index);
                            if (index < _blurredImages.length) {
                              _blurredImages.removeAt(index);
                            } else {
                              _blurredImages = [];
                              _imagesProcessed = false;
                            }
                            if (_selectedImages.isEmpty) {
                              _blurredImages = [];
                              _imagesProcessed = false;
                            }
                          });
                          parentState?.carData.remove('use_blurred_plates');
                          parentState?.invalidatePlateBlurJob();
                          unawaited(_syncMediaDraftToParent());
                          if (_selectedImages.isNotEmpty) {
                            unawaited(parentState?.startBackgroundPlateBlur());
                          }
                        },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
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
            if (hasPhotos) const SizedBox(height: 12),
            if (blurring)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _trLegacyText(
                          context,
                          'Blurring license plates in the background…',
                          ar: 'جارٍ تمويه لوحات المركبات في الخلفية…',
                          ku: 'تابلۆ لە پاشبنەمادا دەشاردرێتەوە…',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (blurReady)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _trLegacyText(
                          context,
                          'Plate blur ready — you can choose later',
                          ar: 'تمويه اللوحات جاهز — يمكنك الاختيار لاحقاً',
                          ku: 'شاردنەوەی تابلۆ ئامادەیە — دواتر هەڵدەبژێردرێت',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library),
                label: Text(
                  hasPhotos ? loc.addMorePhotos : loc.addPhotos,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kFilterAccentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
