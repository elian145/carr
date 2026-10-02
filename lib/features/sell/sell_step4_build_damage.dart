part of 'sell_flow.dart';

mixin _SellStep4BuildDamage on _SellStep4BuildPhotos {
  List<Widget> _sellStep4BuildDamageSection() {
    final loc = AppLocalizations.of(context)!;
    final hasDamage = _damageImages.isNotEmpty;
    final countLabel = hasDamage
        ? '${_damageImages.length}/$_kSellMaxDamagePhotos'
        : '';

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: AppLocalizations.of(context)!.damageCrashPhotosSection,
              valueSummary: countLabel,
            ),
            const SizedBox(height: 12),
            if (hasDamage)
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  return GridView.builder(
                    key: ValueKey(
                      _damageImages.map(ListingImageMedia.source).join('|'),
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
                    itemCount: _damageImages.length,
                    itemBuilder: (context, index) {
                      final image = _damageImages[index];
                      final keyStr = ListingImageMedia.source(image);
                      // Prefer the HEIC/HEIF JPEG preview (if one exists)
                      // for local rendering -- same fix already applied to
                      // the listing-photo grid in
                      // `sell_step4_build_photos.dart`. Falls back to
                      // `localFile` unchanged for every other case
                      // (JPEG/PNG, or no preview yet). Submission still
                      // reads `source()`/`localFile()` directly elsewhere,
                      // never this.
                      final localFile = ListingImageMedia.previewLocalFile(
                        image,
                      );
                      return Stack(
                        key: ValueKey('dmg_$keyStr'),
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                AppPageRoute(
                                  builder: (_) => ListingPreviewGalleryPage(
                                    imageFilesOrUrls: _damageImages.map((item) {
                                      final local =
                                          ListingImageMedia.previewLocalFile(
                                        item,
                                      );
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
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: localFile != null
                                  ? listingLocalFileImage(
                                      localFile,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      key: ValueKey(localFile.path),
                                      errorWidget: Container(
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
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Semantics(
                              button: true,
                              label: AppLocalizations.of(context)!.removeAction,
                              child: InkWell(
                              onTap: () {
                                _removeDamagePhotoAt(index);
                                unawaited(_saveDraft());
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
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            if (hasDamage) const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImportingMedia ? null : _pickDamageImages,
                icon: const Icon(Icons.car_crash_outlined),
                label: Text(
                  hasDamage
                      ? loc.addMoreDamagePhotos
                      : loc.addDamagePhotosCount(
                          '0/$_kSellMaxDamagePhotos',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kFilterAccentColor.withValues(alpha: 0.12),
                  foregroundColor: kFilterAccentColor,
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
