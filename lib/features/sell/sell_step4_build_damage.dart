part of 'sell_flow.dart';

mixin _SellStep4BuildDamage on _SellStep4BuildPhotos {
  List<Widget> _sellStep4BuildDamageSection() {
    return [
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
    ];
  }
}
