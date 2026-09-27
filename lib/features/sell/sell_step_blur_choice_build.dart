part of 'sell_flow.dart';

mixin _SellStepBlurChoiceBuild on _SellStepBlurChoiceLogic {
  Widget _blurPreviewGrid(List<dynamic> images) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    final galleryItems = images.map((item) {
      // Prefer the HEIC/HEIF JPEG preview (if one exists) for local
      // rendering -- this grid renders BOTH the "Original photos" and the
      // "Blurred" lists; blurred images are always server-produced JPEGs
      // (never HEIC), so this is a no-op fallback to `localFile`/`source`
      // for them. Submission uses `original_images`/`blurred_images`
      // (i.e. `source()`/`localFile()`) directly elsewhere, never this.
      final local = ListingImageMedia.previewLocalFile(item);
      return local ?? ListingImageMedia.source(item);
    }).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: 1.25,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final image = images[index];
            final keyStr = ListingImageMedia.source(image);
            final localFile = ListingImageMedia.previewLocalFile(image);
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => ListingPreviewGalleryPage(
                      imageFilesOrUrls: galleryItems,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: localFile != null
                    ? listingLocalFileImage(
                        localFile,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
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
            );
          },
        );
      },
    );
  }

  Widget _choiceTile({
    required bool value,
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectChoice(value),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? kFilterAccentColor.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kFilterAccentColor : const Color(0xFFE8E8ED),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? kFilterAccentColor : Colors.grey.shade700,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? kFilterAccentColor
                            : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? kFilterAccentColor : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI restore (real-device feedback): an earlier fix (see the now-removed
  /// `sell_blur_choice_shows_both_originals_test.dart`) made this ALWAYS
  /// show both the "Original photos" and "Blurred photos" grids
  /// simultaneously, regardless of which radio tile was selected -- so the
  /// two `_choiceTile`s above were purely cosmetic and never actually
  /// changed what was rendered here. The user does not want that: exactly
  /// ONE side must be visible at a time, matching the selected choice --
  /// "No, keep original photos" shows only the original grid; "Yes, use
  /// blurred photos" shows only the blurred grid (or its
  /// blurring/not-ready states); no choice made yet shows neither (the
  /// original, pre-existing behavior before either tile is tapped).
  ///
  /// This is a presentation-only change. `applySellPlateBlurChoice` in
  /// `sell_plate_blur_choice.dart` (covered by
  /// `sell_plate_blur_choice_test.dart`, untouched by this fix) still reads
  /// BOTH `original_images` and `blurred_images` when committing a choice,
  /// and neither list is ever cleared or overwritten here -- only which one
  /// is rendered changes. The original/unblurred grid still renders through
  /// `_blurPreviewGrid`, which already resolves
  /// `ListingImageMedia.previewLocalFile()` (not the raw `localFile()`), so
  /// HEIF originals keep working exactly as before.
  Widget _previewSection({
    required _SellCarPageState? parent,
    required List<dynamic> originals,
    required List<dynamic> blurred,
    required List<dynamic> damageOriginals,
    required List<dynamic> damageBlurred,
  }) {
    final loc = AppLocalizations.of(context)!;
    final showMainOriginals = originals.isNotEmpty;
    final showDamageOriginals = damageOriginals.isNotEmpty;
    if (!showMainOriginals && !showDamageOriginals) {
      _debugLog(
        'BLUR CHOICE SCREEN: no original photos to preview yet '
        '(originals=${originals.length}, damageOriginals=${damageOriginals.length})',
      );
      return const SizedBox.shrink();
    }

    final blurring = parent?.isBlurringPlates == true;
    final blurReady = parent?.hasBlurredPlatesReady == true;
    final showMainBlurred = blurred.isNotEmpty;
    final showDamageBlurred = damageBlurred.isNotEmpty;

    _debugLog(
      'BLUR CHOICE SCREEN: originals=${originals.length} '
      'damageOriginals=${damageOriginals.length} blurred=${blurred.length} '
      'damageBlurred=${damageBlurred.length} blurring=$blurring '
      'blurReady=$blurReady choice=$_useBlurredPlates',
    );

    Widget labeledGrid(String title, List<dynamic> images) {
      if (images.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 10),
          _blurPreviewGrid(images),
          const SizedBox(height: 14),
        ],
      );
    }

    // No choice made yet -- show neither grid (matches the original,
    // pre-"always show both" behavior).
    if (_useBlurredPlates == null) {
      return const SizedBox.shrink();
    }

    if (_useBlurredPlates == false) {
      // "No, keep original photos" -- ONLY the original/unblurred grid.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          labeledGrid(loc.originalPhotos, originals),
          labeledGrid(loc.originalDamagePhotos, damageOriginals),
        ],
      );
    }

    // _useBlurredPlates == true: "Yes, use blurred photos" -- ONLY the
    // blurred grid (or its blurring/not-ready state), never the originals.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (blurring)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kFilterAccentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: kFilterAccentColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.stillBlurringPlatesInTheBackgroundPhotosWillAppearHereWhenReady,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          )
        else if (blurReady) ...[
          labeledGrid(loc.blurredPhotos, blurred),
          labeledGrid(loc.blurredDamagePhotos, damageBlurred),
          if (!showMainBlurred && !showDamageBlurred)
            Text(
              loc.noPhotosAvailable,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
        ] else ...[
          Text(
            loc.blurredPhotosAreNotReadyYet,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _retryBackgroundBlur,
              icon: const Icon(Icons.refresh),
              label: Text(loc.blurPlatesNow),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final carData = parent?.carData ?? <String, dynamic>{};
    final originals = _originalImages(carData);
    final blurred = _blurredImages(carData);
    final damageOriginals = _damageOriginalImages(carData);
    final damageBlurred = _damageBlurredImages(carData);
    final blurring = parent?.isBlurringPlates == true;
    final blurReady = parent?.hasBlurredPlatesReady == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterSectionHeader(
                  title: AppLocalizations.of(context)!.blurPlates,
                  requiredField: true,
                  valueSummary: _useBlurredPlates == null
                      ? AppLocalizations.of(context)!.tapToSelect
                      : (_useBlurredPlates!
                          ? AppLocalizations.of(context)!.yesBlurPlates
                          : AppLocalizations.of(context)!.noKeepOriginal),
                ),
                const SizedBox(height: 12),
                _choiceTile(
                  value: true,
                  selected: _useBlurredPlates == true,
                  icon: Icons.blur_on,
                  title: AppLocalizations.of(context)!.yesUseBlurredPhotos,
                  subtitle: AppLocalizations.of(context)!.hideLicensePlatesOnYourListing,
                ),
                const SizedBox(height: 10),
                _choiceTile(
                  value: false,
                  selected: _useBlurredPlates == false,
                  icon: Icons.photo_outlined,
                  title: AppLocalizations.of(context)!.noKeepOriginalPhotos,
                  subtitle: AppLocalizations.of(context)!.publishThePhotosExactlyAsYouUploadedThem,
                ),
                _previewSection(
                  parent: parent,
                  originals: originals,
                  blurred: blurred,
                  damageOriginals: damageOriginals,
                  damageBlurred: damageBlurred,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          buildSellWizardNavRow(
            context,
            onPrevious: () {
              context
                  .findAncestorStateOfType<_SellCarPageState>()
                  ?._goToPreviousStep();
            },
            onNext: () {
              if (_useBlurredPlates == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.pleaseChooseWhetherToBlurPlates,
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (_useBlurredPlates == true && blurring) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.pleaseWaitForPlateBlurringToFinish,
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              if (_useBlurredPlates == true && !blurReady) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.blurPlatesFirstOrChooseToKeepOriginals,
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              _selectChoice(_useBlurredPlates!);
              context
                  .findAncestorStateOfType<_SellCarPageState>()
                  ?._goToNextStep();
            },
          ),
        ],
      ),
    );
  }
}
