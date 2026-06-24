part of 'sell_flow.dart';

mixin _SellStep4Build on _SellStep4BuildVideos {
  List<Widget> _sellStep4BuildNavSection() {
    return [
      const SizedBox(height: 32),
      buildSellWizardNavRow(
        context,
        onPrevious: () {
          unawaited(_syncMediaDraftToParent());
          context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._goToPreviousStep();
        },
        onNext: () {
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

          unawaited(_syncMediaDraftToParent());
          final parentState =
              context.findAncestorStateOfType<_SellCarPageState>();
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
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
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
    );
  }
}
