part of 'sell_flow.dart';

mixin _SellStep4BuildPhotos on _SellStep4BuildIntro {
  List<Widget> _sellStep4BuildPhotosSection() {
    return [
      // Photos Section — 2 per row, full width (like home listing cards), tap to open full-screen
      Text(
        _photosRequiredTitleGlobal(context),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      if (_selectedImages.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _trLegacyText(
              context,
              'Tap the star on a photo to set it as the cover image shown first in your listing.',
              ar: 'اضغط على النجمة على الصورة لتعيينها كصورة الغلاف التي تظهر أولاً في إعلانك.',
              ku: 'کرتە بکە لە ئەستێرەکە لەسەر وێنەکە بۆ ئەوەی وەک وێنەی سەرەکی یەکەم لە ڕیکلامەکەتدا دەربکەوێت.',
            ),
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      SizedBox(height: 12),
      if (_selectedImages.isNotEmpty)
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = 8.0;
            return GridView.builder(
              key: ValueKey(
                _selectedImages.map(ListingImageMedia.source).join('|'),
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
                              imageFilesOrUrls: _selectedImages.map((item) {
                                final local = ListingImageMedia.localFile(item);
                                return local ?? ListingImageMedia.source(item);
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
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade700,
                            width: isPrimary ? 2 : 1,
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
                        child: localFile != null
                            ? Image.file(
                                File(localFile.path),
                                fit: BoxFit.cover,
                                alignment: ListingImageMedia.coverAlignment(
                                  image,
                                ),
                                width: double.infinity,
                                height: double.infinity,
                                key: ValueKey(localFile.path),
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      color: Colors.grey.shade800,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 32,
                                      ),
                                    ),
                              )
                            : _listingNetworkImage(
                                keyStr.startsWith('http')
                                    ? keyStr
                                    : _buildFullImageUrl(keyStr),
                                fit: BoxFit.cover,
                                alignment: ListingImageMedia.coverAlignment(
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
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                _trLegacyText(
                                  context,
                                  'Cover',
                                  ar: 'الغلاف',
                                  ku: 'سەرەکی',
                                ),
                                style: TextStyle(
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
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.all(6),
                            child: Icon(
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
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: InkWell(
                        onTap: () => _adjustImageCrop(index),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.crop,
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
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = AppResponsive.isCompactPhone(context);
          final buttonWidth = compact
              ? constraints.maxWidth
              : (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: buttonWidth,
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.photo_library),
                  label: Text(
                    _selectedImages.isEmpty
                        ? AppLocalizations.of(context)!.addPhotos
                        : AppLocalizations.of(context)!.addMorePhotos,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              SizedBox(
                width: buttonWidth,
                child: ElevatedButton.icon(
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              ),
            ],
          );
        },
      ),
      SizedBox(height: 24),
    ];
  }
}
