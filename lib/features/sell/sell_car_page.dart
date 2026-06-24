part of 'sell_flow.dart';

class SellCarPage extends StatefulWidget {
  const SellCarPage({
    super.key,
    this.initialDraftSnapshot,
    this.startFreshListing = false,
  });

  final Map<String, dynamic>? initialDraftSnapshot;
  final bool startFreshListing;

  @override
  State<SellCarPage> createState() => _SellCarPageState();
}

class _SellCarPageState extends _SellCarPageFields with _SellCarPageDraftPersist, _SellCarPageDraftBanner {
  @override
  void initState() {
    super.initState();
    int controllerInitialPage = 0;
    final initialDraft = widget.initialDraftSnapshot;
    if (initialDraft != null) {
      controllerInitialPage =
          _readSellDraftStepDynamic(initialDraft['currentStep'])
              .clamp(0, _SellCarPageFields._kSellStepCount - 1);
    }
    _pageController = PageController(initialPage: controllerInitialPage);
    if (initialDraft != null) {
      _hideDraftBanner = true;
      _currentDraftId = (initialDraft['draftId'] ?? _newSellDraftId()).toString();
      _applyDraftSnapshot(initialDraft);
      unawaited(_reconcileSellStepWithPrefsAfterDraftOpen());
      // Some builds align [PageView] after layout; force the visible page once attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          final t = currentStep.clamp(0, _SellCarPageFields._kSellStepCount - 1);
          final cur = _pageController.page?.round();
          if (cur != t) {
            _pageController.jumpToPage(t);
          }
        });
      });
    } else if (widget.startFreshListing) {
      _hideDraftBanner = true;
      _hasDraftSnapshot = false;
      _draftPreviewStep = 0;
      _draftPreviewCarData = null;
      _currentDraftId = _newSellDraftId();
      carData = <String, dynamic>{};
      completedSteps.clear();
      currentStep = 0;
      unawaited(_initFreshListingSession());
    } else {
      unawaited(_loadSellDraftPreview());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _goToPreviousStep();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _isEditMode
                ? AppLocalizations.of(context)!.editListingTitle
                : AppLocalizations.of(context)!.addListingTitle,
          ),
          backgroundColor: Color(0xFFFF6B00),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: _goToPreviousStep,
          ),
        ),
        body: Container(
          decoration: AppThemes.shellBackgroundDecoration(
            Theme.of(context).brightness,
          ),
          child: Column(
            children: [
              if (!_isEditMode) _buildDraftBanner(),
              // Progress indicator
              Container(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: List.generate(5, (index) {
                    bool isCompleted = completedSteps.contains(index);
                    bool isCurrent = index == currentStep;
                    bool isAccessible = index <= currentStep || isCompleted;

                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 4),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green
                              : isCurrent
                              ? Color(0xFFFF6B00)
                              : isAccessible
                              ? Color(0xFFFF6B00).withValues(alpha: 0.5)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Step indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.stepXOf5(currentStep + 1),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _getStepTitle(context, currentStep),
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Page content
              Expanded(
                child: PageView.builder(
                  key: ValueKey(_sellPageResetToken),
                  controller: _pageController,
                  physics:
                      NeverScrollableScrollPhysics(), // Disable swipe scrolling
                  // Do not persist from [onPageChanged]: during [nextPage] the
                  // callback can report page 0 and race async saves, overwriting
                  // the real step (e.g. user on step 2). Step is saved from
                  // [_goToNextStep]/[_goToPreviousStep], field syncs, and [dispose].
                  itemCount: _SellCarPageFields._kSellStepCount,
                  itemBuilder: (context, index) => _sellStepChild(index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepTitle(BuildContext context, int step) {
    final l = AppLocalizations.of(context)!;
    switch (step) {
      case 0:
        return l.basicInformationTitle;
      case 1:
        return l.carDetailsTitle;
      case 2:
        return l.pricingContactTitle;
      case 3:
        return l.photosVideosTitle;
      case 4:
        return l.reviewSubmitTitle;
      default:
        return '';
    }
  }

  // Method to validate if a step is completed
  bool _isStepCompleted(int step) {
    switch (step) {
      case 0: // Basic Information
        return carData['brand'] != null &&
            carData['brand'].toString().isNotEmpty &&
            carData['model'] != null &&
            carData['model'].toString().isNotEmpty &&
            carData['trim'] != null &&
            carData['trim'].toString().isNotEmpty &&
            carData['year'] != null &&
            carData['year'].toString().isNotEmpty;
      case 1: // Car Details
        return carData['mileage'] != null &&
            carData['mileage'].toString().isNotEmpty &&
            carData['condition'] != null &&
            carData['condition'].toString().isNotEmpty &&
            carData['transmission'] != null &&
            carData['transmission'].toString().isNotEmpty &&
            carData['fuel_type'] != null &&
            carData['fuel_type'].toString().isNotEmpty &&
            carData['body_type'] != null &&
            carData['body_type'].toString().isNotEmpty &&
            carData['color'] != null &&
            carData['color'].toString().isNotEmpty &&
            carData['seating'] != null &&
            carData['seating'].toString().isNotEmpty &&
            carData['drive_type'] != null &&
            carData['drive_type'].toString().isNotEmpty &&
            carData['region_specs'] != null &&
            carData['region_specs'].toString().trim().isNotEmpty &&
            isValidCarRegionSpecCode(
              carData['region_specs'].toString().trim().toLowerCase(),
            ) &&
            carData['title_status'] != null &&
            carData['title_status'].toString().isNotEmpty;
      case 2: // Pricing & Contact
        return carData['city'] != null &&
            carData['city'].toString().isNotEmpty &&
            carData['contact_phone'] != null &&
            carData['contact_phone'].toString().isNotEmpty;
      case 3: // Photos & Videos
        return carData['images'] != null &&
            (carData['images'] as List).isNotEmpty;
      case 4: // Review & Submit
        return true; // This step is always accessible for review
      default:
        return false;
    }
  }

  // Method to navigate to next step with validation
  void _goToNextStep() {
    _dismissKeyboard();
    if (currentStep < _SellCarPageFields._kSellStepCount - 1) {
      if (_isStepCompleted(currentStep)) {
        completedSteps.add(currentStep);
        setState(() {
          currentStep++;
        });
        unawaited(_saveDraftCurrentStep());
        unawaited(_saveSellDraftSnapshot());
        _pageController.nextPage(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please complete all required fields before proceeding',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Method to navigate to previous step
  void _goToPreviousStep() {
    _dismissKeyboard();
    if (currentStep > 0) {
      setState(() {
        currentStep--;
      });
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // Bottom nav uses pushReplacementNamed to open Sell, so there is no
      // route below us — pop would show an empty/black screen.
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  /// Jump to a wizard index and keep [currentStep] + persisted draft in sync
  /// (used e.g. when validation sends the user back to a specific step).
  void _jumpSellWizardToIndex(int index) {
    _dismissKeyboard();
    final clamped = index.clamp(0, _SellCarPageFields._kSellStepCount - 1);
    setState(() {
      currentStep = clamped;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(clamped);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(clamped);
        }
      });
    }
    unawaited(_saveDraftCurrentStep());
    unawaited(_saveSellDraftSnapshot());
  }

  @override
  void dispose() {
    if (!_skipDraftPersistOnDispose &&
        !LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
    }
    _pageController.dispose();
    super.dispose();
  }
}
