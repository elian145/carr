part of 'sell_flow.dart';

mixin _SellStepBlurChoiceBuild on _SellStepBlurChoiceLogic {
  Widget _blurPreviewGrid(List<dynamic> images) {
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    final galleryItems = images.map((item) {
      final local = ListingImageMedia.localFile(item);
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
            final localFile = ListingImageMedia.localFile(image);
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
                    ? Image.file(
                        File(localFile.path),
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

  Widget _previewSection({
    required _SellCarPageState? parent,
    required List<dynamic> originals,
    required List<dynamic> blurred,
    required List<dynamic> damageOriginals,
    required List<dynamic> damageBlurred,
  }) {
    if (_useBlurredPlates == null) {
      return const SizedBox.shrink();
    }

    final blurring = parent?.isBlurringPlates == true;
    final blurReady = parent?.hasBlurredPlatesReady == true;
    final showMainBlurred = blurred.isNotEmpty;
    final showDamageBlurred = damageBlurred.isNotEmpty;
    final showMainOriginals = originals.isNotEmpty;
    final showDamageOriginals = damageOriginals.isNotEmpty;

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

    if (_useBlurredPlates == true) {
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
                      AppLocalizations.of(context)!.stillBlurringPlatesInTheBackgroundPhotosWillAppearHereWhenReady,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            )
          else if (blurReady) ...[
            labeledGrid(
              AppLocalizations.of(context)!.blurredPhotos,
              blurred,
            ),
            labeledGrid(
              AppLocalizations.of(context)!.blurredDamagePhotos,
              damageBlurred,
            ),
            if (!showMainBlurred && !showDamageBlurred)
              Text(
                AppLocalizations.of(context)!.noPhotosAvailable,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
          ] else ...[
            Text(
              AppLocalizations.of(context)!.blurredPhotosAreNotReadyYet,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _retryBackgroundBlur,
                icon: const Icon(Icons.refresh),
                label: Text(
                  AppLocalizations.of(context)!.blurPlatesNow,
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
        ],
      );
    }

    // Original photos choice
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        labeledGrid(
          AppLocalizations.of(context)!.originalPhotos,
          originals,
        ),
        labeledGrid(
          AppLocalizations.of(context)!.originalDamagePhotos,
          damageOriginals,
        ),
        if (!showMainOriginals && !showDamageOriginals)
          Text(
            AppLocalizations.of(context)!.noPhotosAvailable,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
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
