part of 'sell_flow.dart';

mixin _SellStep4Build on _SellStep4BuildVideos {
  List<Widget> _sellStep4BuildNavSection() {
    return [
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
