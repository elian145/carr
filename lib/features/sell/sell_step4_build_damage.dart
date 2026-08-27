part of 'sell_flow.dart';

mixin _SellStep4BuildDamage on _SellStep4BuildPhotos {
  List<Widget> _sellStep4BuildDamageSection() {
    final loc = AppLocalizations.of(context)!;
    final hasDamage = _damageImages.isNotEmpty;
    final countLabel = hasDamage
        ? loc.addDamagePhotosCount(
            '${_damageImages.length}/$_kSellMaxDamagePhotos',
          )
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
                      _damageImages
                          .map((e) => e is XFile ? e.path : e.toString())
                          .join('|'),
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
                      final keyStr =
                          image is XFile ? image.path : image.toString();
                      return Stack(
                        key: ValueKey('dmg_$keyStr'),
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                AppPageRoute(
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
                                  color: Colors.grey.shade300,
                                ),
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
                                      (image
                                              .toString()
                                              .trim()
                                              .startsWith('http'))
                                          ? image.toString().trim()
                                          : _buildFullImageUrl(
                                              image.toString(),
                                            ),
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
                                final parentState = context
                                    .findAncestorStateOfType<_SellCarPageState>();
                                setState(() {
                                  _damageImages.removeAt(index);
                                });
                                parentState?.carData.remove('use_blurred_plates');
                                parentState?.invalidatePlateBlurJob();
                                unawaited(_syncMediaDraftToParent());
                                unawaited(_saveDraft());
                                if (_damageImages.isNotEmpty ||
                                    _selectedImages.isNotEmpty) {
                                  unawaited(
                                    parentState?.startBackgroundPlateBlur(),
                                  );
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
                  loc.addDamagePhotosCount(
                    '${_damageImages.length}/$_kSellMaxDamagePhotos',
                  ),
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
