part of 'sell_flow.dart';

abstract class _SellCarPageFields extends State<SellCarPage> {
  int currentStep = 0;
  late final PageController _pageController;
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  bool _hasDraftSnapshot = false;
  bool _hideDraftBanner = false;
  int _draftPreviewStep = 0;
  Map<String, dynamic>? _draftPreviewCarData;
  int _sellPageResetToken = 0;
  int _draftResumeToken = 0;
  String _currentDraftId = _newSellDraftId();
  bool _skipDraftPersistOnDispose = false;
  String? _editListingId;
  final Set<String> _verifiedListingPhones = <String>{};

  bool get _isEditMode => (_editListingId ?? '').trim().isNotEmpty;

  // Car data that will be passed between steps
  Map<String, dynamic> carData = {};

  // Track completed steps
  Set<int> completedSteps = {};

  /// Prefer [SellWizardSteps.count]; kept as alias for call sites in this library.
  static const int _kSellStepCount = SellWizardSteps.count;

  /// Step 2 key bumps when catalog specs are applied so Car Details reloads from [carData].
  Widget _sellStepChild(int index) {
    if (index == SellWizardSteps.reviewSubmit) {
      return SellStep5Page(key: ValueKey(_step5ImagesKey));
    }
    switch (index) {
      case SellWizardSteps.photos:
        return const SellStep4Page();
      case SellWizardSteps.basicInfo:
        return SellStep1Page(
          resumeDraftToken: _draftResumeToken,
          key: ValueKey('s1_$_draftResumeToken'),
        );
      case SellWizardSteps.carDetails:
        return SellStep2Page(
          key: ValueKey(
            's2_${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}_${carData['brand']}_${carData['model']}_${carData['trim']}_${carData['year']}',
          ),
          specsHydrateToken:
              '${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}',
        );
      case SellWizardSteps.pricingContact:
        return const SellStep3Page();
      case SellWizardSteps.plateBlur:
        return const SellStepBlurChoicePage();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Key that changes when carData images/videos change so Review rebuilds.
  String get _step5ImagesKey {
    final imgs = carData['images'];
    final vids = carData['videos'];
    final dmg = carData['damage_images'];
    final blurChoice = carData['use_blurred_plates'];
    final primaryIndex = carData['primary_image_index'] ?? 0;
    final dmgPart = (dmg == null || dmg is! List || dmg.isEmpty)
        ? ''
        : dmg.map(ListingImageMedia.source).join('|');
    final imgPart = (imgs == null || imgs is! List || imgs.isEmpty)
        ? ''
        : imgs.map(ListingImageMedia.source).join('|');
    final vidPart = (vids == null || vids is! List || vids.isEmpty)
        ? ''
        : vids.map(ListingImageMedia.source).join('|');
    final specPart = [
      carData['brand'],
      carData['model'],
      carData['year'],
      carData['price'],
      carData['mileage'],
      carData['cylinder_count'],
      carData['engine_size'],
      carData['region_specs'],
      carData['transmission'],
      carData['fuel_type'],
      carData['city'],
    ].join('|');
    if (imgPart.isEmpty && vidPart.isEmpty && dmgPart.isEmpty) {
      return '0::$blurChoice::$primaryIndex::$specPart';
    }
    return '$imgPart::$vidPart::$dmgPart::$blurChoice::$primaryIndex::$specPart';
  }
}
