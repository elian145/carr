part of 'sell_flow.dart';

mixin _SellStep4Build on _SellStep4BuildVideos {
  List<Widget> _sellStep4BuildNavSection() {
    return [
      const SizedBox(height: 12),
      buildSellWizardNavRow(
        context,
        onPrevious: _isImportingMedia
            ? null
            : () {
                unawaited(_syncMediaDraftToParent());
                context
                    .findAncestorStateOfType<_SellCarPageState>()
                    ?._goToPreviousStep();
              },
        onNext: _isImportingMedia
            ? null
            : () async {
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

          await _syncMediaDraftToParent();
          if (!mounted) return;
          final parentState =
              context.findAncestorStateOfType<_SellCarPageState>();
          if (parentState != null) {
            parentState.carData['original_images'] =
                List<dynamic>.from(_selectedImages);
            // Preserve any background-blurred results already on the parent.
            final existingBlurred = parentState.carData['blurred_images'];
            if (_blurredImages.isNotEmpty) {
              parentState.carData['blurred_images'] =
                  List<dynamic>.from(_blurredImages);
            } else if (existingBlurred is! List || existingBlurred.isEmpty) {
              parentState.carData['blurred_images'] = <dynamic>[];
            }
            parentState.carData['images'] =
                List<dynamic>.from(_selectedImages);
            parentState.carData['primary_image_index'] = _primaryImageIndex;
            parentState.carData['original_damage_images'] =
                List<dynamic>.from(_damageImages);
            parentState.carData['damage_images'] =
                List<dynamic>.from(_damageImages);
            parentState.carData['videos'] = List<XFile>.from(
              _selectedVideos,
            );
            parentState.carData['images_processed'] =
                parentState.hasBlurredPlatesReady || _imagesProcessed;
            parentState.carData['sell_wizard_v2'] = true;
            // Keep blur running after leaving photos.
            if (!parentState.hasBlurredPlatesReady &&
                !parentState.isBlurringPlates &&
                _selectedImages.isNotEmpty) {
              unawaited(parentState.startBackgroundPlateBlur());
            }
            // Media-readiness contract fix: this pre-create "prestage"
            // upload (upload now, poll to completion, rewrite `carData`
            // to a remote URL, all before `create_car()` even runs) is
            // EDIT-MODE ONLY now -- kicking it off for a new listing
            // would just race/duplicate the exact upload+processing work
            // `submitFast()`'s own Phase A already does AFTER
            // `create_car()`, for no benefit (Phase A is already fast
            // enough on its own -- see `sell_step5_logic.dart`'s
            // `_submitListing`). Edit-mode keeps this exactly as before.
            if (parentState._isEditMode) {
              unawaited(parentState.startBackgroundPhotoPrestage());
            }
            parentState._goToNextStep();
          }
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._sellStep4BuildIntroSection(),
              ..._sellStep4BuildPhotosSection(),
              ..._sellStep4BuildDamageSection(),
              ..._sellStep4BuildVideosSection(),
              ..._sellStep4BuildNavSection(),
            ],
          ),
        ),
        if (_isImportingMedia)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      // Distinct "Preparing video…" state while a picked
                      // video is being probed/compressed (task
                      // requirement) -- never shown for a plain photo
                      // import, and never counted as upload progress
                      // (upload progress only starts once
                      // `PendingSellSubmissionService` runs, well after
                      // this overlay is gone).
                      if (_videoPrepPhase != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)!.sellPreparingVideo,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
