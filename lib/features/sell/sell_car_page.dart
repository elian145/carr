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

class _SellCarPageState extends State<SellCarPage> {
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

  bool get _isEditMode => (_editListingId ?? '').trim().isNotEmpty;

  // Car data that will be passed between steps
  Map<String, dynamic> carData = {};

  // Track completed steps
  Set<int> completedSteps = {};

  static const int _kSellStepCount = 5;

  /// Step 2 key bumps when catalog specs are applied so Car Details reloads from [carData].
  Widget _sellStepChild(int index) {
    if (index == 4) {
      return SellStep5Page(key: ValueKey(_step5ImagesKey));
    }
    switch (index) {
      case 0:
        return SellStep1Page(
          resumeDraftToken: _draftResumeToken,
          key: ValueKey('s1_$_draftResumeToken'),
        );
      case 1:
        return SellStep2Page(
          key: ValueKey(
            's2_${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}_${carData['brand']}_${carData['model']}_${carData['trim']}_${carData['year']}',
          ),
          specsHydrateToken:
              '${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}',
        );
      case 2:
        return const SellStep3Page();
      case 3:
        return const SellStep4Page();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Key that changes when carData images/videos change so Step 5 (summary) rebuilds.
  String get _step5ImagesKey {
    final imgs = carData['images'];
    final vids = carData['videos'];
    final dmg = carData['damage_images'];
    final dmgPart = (dmg == null || dmg is! List || dmg.isEmpty)
        ? ''
        : dmg.map((e) => e is XFile ? e.path : e.toString()).join('|');
    final imgPart = (imgs == null || imgs is! List || imgs.isEmpty)
        ? ''
        : imgs.map((e) => e is XFile ? e.path : e.toString()).join('|');
    final vidPart = (vids == null || vids is! List || vids.isEmpty)
        ? ''
        : vids.map((e) => e is XFile ? e.path : e.toString()).join('|');
    if (imgPart.isEmpty && vidPart.isEmpty && dmgPart.isEmpty) return '0';
    return '$imgPart::$vidPart::$dmgPart';
  }

  /// Non-empty field check for draft persistence (aligned with step sync keys).
  bool _sellPersistFieldNonEmpty(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is num) return true;
    if (v is bool) return v;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return v.toString().trim().isNotEmpty;
  }

  /// Highest wizard index (0–4) that already has saved field data.
  /// Used so "Back" from step 2 to step 1 does not persist [currentStep] = 0
  /// while car details (e.g. transmission) remain in [carData].
  int _deepestSellWizardStepHintFromCarData() {
    final d = carData;
    int maxIdx = 0;
    if (_sellPersistFieldNonEmpty(d['mileage']) ||
        _sellPersistFieldNonEmpty(d['condition']) ||
        _sellPersistFieldNonEmpty(d['transmission']) ||
        _sellPersistFieldNonEmpty(d['fuel_type']) ||
        _sellPersistFieldNonEmpty(d['body_type']) ||
        _sellPersistFieldNonEmpty(d['color']) ||
        _sellPersistFieldNonEmpty(d['drive_type']) ||
        _sellPersistFieldNonEmpty(d['region_specs']) ||
        _sellPersistFieldNonEmpty(d['seating']) ||
        _sellPersistFieldNonEmpty(d['engine_size']) ||
        _sellPersistFieldNonEmpty(d['cylinder_count']) ||
        _sellPersistFieldNonEmpty(d['title_status']) ||
        _sellPersistFieldNonEmpty(d['damaged_parts'])) {
      maxIdx = 1;
    }
    if (_sellPersistFieldNonEmpty(d['price']) ||
        _sellPersistFieldNonEmpty(d['city']) ||
        _sellPersistFieldNonEmpty(d['contact_phone']) ||
        _sellPersistFieldNonEmpty(d['plate_type']) ||
        _sellPersistFieldNonEmpty(d['plate_city']) ||
        _sellPersistFieldNonEmpty(d['description'])) {
      maxIdx = math.max(maxIdx, 2);
    }
    final imgs = d['images'];
    if (imgs is List && imgs.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    final dmg = d['damage_images'];
    if (dmg is List && dmg.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    final vids = d['videos'];
    if (vids is List && vids.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    return maxIdx.clamp(0, _kSellStepCount - 1);
  }

  int _effectivePersistedDraftStep() {
    return math
        .max(currentStep, _deepestSellWizardStepHintFromCarData())
        .clamp(0, _kSellStepCount - 1);
  }

  void _dismissKeyboard() => _dismissAnyKeyboard(context);

  Future<void> _saveDraftCurrentStep() async {
    if (_isEditMode) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_draftCurrentStepKey, _effectivePersistedDraftStep());
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _initFreshListingSession() async {
    await LegacySellDraftPrefs.clearActiveStepStorage();
    LegacySellDraftPrefs.allowPersist();
    if (!mounted) return;
    setState(() {
      _sellPageResetToken++;
    });
  }

  Future<void> _clearAllSellDrafts() async {
    try {
      _skipDraftPersistOnDispose = true;
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_draftCurrentStepKey);
      await sp.remove(_draftSnapshotKey);
      await sp.remove(_sellDraftArchiveKey);
      await LegacySellDraftPrefs.clearActiveStorage();
      if (mounted) {
        setState(() {
          carData = <String, dynamic>{};
          _hasDraftSnapshot = false;
          _currentDraftId = _newSellDraftId();
        });
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _clearSubmittedDraftOnly({String? draftId}) async {
    try {
      _skipDraftPersistOnDispose = true;
      final sp = await SharedPreferences.getInstance();
      final String resolvedDraftId =
          (draftId ?? _currentDraftId).toString().trim();

      await sp.remove(_draftCurrentStepKey);
      await sp.remove(_draftSnapshotKey);
      await sp.remove('legacy_sell_draft_step1_v1');
      await sp.remove('legacy_sell_draft_step2_v1');
      await sp.remove('legacy_sell_draft_step3_v1');
      await sp.remove('legacy_sell_draft_step4_v1');

      if (resolvedDraftId.isNotEmpty) {
        final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
        archive.removeWhere(
          (item) => item['draftId']?.toString() == resolvedDraftId,
        );
        await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
      }

      if (mounted) {
        setState(() {
          carData = <String, dynamic>{};
          _hasDraftSnapshot = false;
          _currentDraftId = _newSellDraftId();
        });
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  dynamic _draftValue(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is XFile) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _draftValue(v)));
    }
    if (value is Iterable) {
      return value.map(_draftValue).toList();
    }
    return value.toString();
  }

  bool _hasMeaningfulDraftValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return value != 0;
    if (value is bool) return value;
    if (value is XFile) return value.path.trim().isNotEmpty;
    if (value is Map) {
      for (final entry in value.entries) {
        if (_hasMeaningfulDraftValue(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_hasMeaningfulDraftValue(item)) return true;
      }
      return false;
    }
    return value.toString().trim().isNotEmpty;
  }

  Future<void> _saveSellDraftSnapshot() async {
    if (_isEditMode) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final hasExistingSnapshot =
          (sp.getString(_draftSnapshotKey)?.trim().isNotEmpty == true);
      if (!_hasMeaningfulDraftValue(carData)) {
        if (hasExistingSnapshot) {
          if (mounted) {
            setState(() {
              _hasDraftSnapshot = true;
            });
          }
          return;
        }
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        await LegacySellDraftPrefs.clearActiveStepStorage();
        if (mounted) {
          setState(() {
            _hasDraftSnapshot = false;
          });
        }
        return;
      }
      final persistedStep = _effectivePersistedDraftStep();
      final storedCarData =
          await SellDraftMediaPersistence.prepareCarDataForStorage(
        carData,
        draftId: _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
      );
      if (mounted) {
        setState(() {
          carData = storedCarData;
        });
      } else {
        carData = storedCarData;
      }
      final snapshot = <String, dynamic>{
        'draftId': _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
        'currentStep': persistedStep,
        'carData': _draftValue(storedCarData),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _currentDraftId = snapshot['draftId'].toString();
      await sp.setString(
        _draftSnapshotKey,
        json.encode(snapshot),
      );
      await sp.setInt(_draftCurrentStepKey, persistedStep);
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
      archive.removeWhere((draft) => draft['draftId'] == _currentDraftId);
      archive.insert(0, snapshot);
      await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _restoreSellDraftSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final jsonStep = _readSellDraftStepDynamic(data['currentStep']);
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final restoredStep = _mergeSellDraftStep(
        jsonStep: jsonStep,
        prefsStep: prefsStep,
      );
      _currentDraftId = (data['draftId'] ?? _newSellDraftId()).toString();
      final rawCarData = data['carData'];
      final restoredCarData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      final isPlaceholder = data['isPlaceholder'] == true;
      if (!_hasMeaningfulDraftValue(restoredCarData) && !isPlaceholder) {
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        currentStep = restoredStep.clamp(0, _kSellStepCount - 1);
        carData = _resolveCarDataMedia(restoredCarData);
        _hasDraftSnapshot = true;
        _draftPreviewStep = currentStep;
        _draftPreviewCarData = carData;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(currentStep);
        }
      });
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _resumeSellDraft() async {
    setState(() {
      _draftResumeToken++;
    });
    await _restoreSellDraftSnapshot();
  }

  Future<void> _reconcileSellStepWithPrefsAfterDraftOpen() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      int fromDisk = currentStep;
      final raw = sp.getString(_draftSnapshotKey);
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
            fromDisk = _readSellDraftStepDynamic(m['currentStep']);
          }
        } catch (e, st) { logNonFatal(e, st); }
      }
      final merged = _maxSellDraftStep(
        currentStep,
        fromDisk,
        prefsStep ?? 0,
      );
      if (merged == currentStep) return;
      setState(() {
        currentStep = merged;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(currentStep);
        }
      });
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
    } catch (e, st) { logNonFatal(e, st); }
  }

  Map<String, dynamic> _resolveCarDataMedia(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    for (final key in ['images', 'damage_images', 'videos']) {
      if (copy[key] is List) {
        copy[key] = SellDraftMediaPersistence.resolveDynamicMediaList(
          List<dynamic>.from(copy[key] as List),
        );
      }
    }
    return copy;
  }

  void _applyDraftSnapshot(
    Map<String, dynamic> snapshot, {
    bool restoreCurrentStep = true,
  }) {
    final currentStepValue = _readSellDraftStepDynamic(snapshot['currentStep']);
    final rawCarData = snapshot['carData'];
    final restoredCarData = rawCarData is Map
        ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
        : <String, dynamic>{};
    final isPlaceholder = snapshot['isPlaceholder'] == true;
    if (!_hasMeaningfulDraftValue(restoredCarData) && !isPlaceholder) return;
    _currentDraftId = (snapshot['draftId'] ?? _newSellDraftId()).toString();
    final editId = (restoredCarData['_editListingId'] ?? '').toString().trim();
    if (editId.isNotEmpty) {
      _editListingId = editId;
      _skipDraftPersistOnDispose = true;
    }

    if (restoreCurrentStep) {
      currentStep = currentStepValue.clamp(0, _kSellStepCount - 1);
    }
    carData = _resolveCarDataMedia(restoredCarData);
    _hasDraftSnapshot = true;
    _draftPreviewStep = currentStep;
    _draftPreviewCarData = carData;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(currentStep);
      }
    });
  }

  Future<void> _loadSellDraftPreview() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
          _draftPreviewStep = 0;
          _draftPreviewCarData = null;
        });
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final restoredStep = _readSellDraftStepDynamic(data['currentStep']);
      final rawCarData = data['carData'];
      final restoredCarData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      if (!_hasMeaningfulDraftValue(restoredCarData)) {
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
          _draftPreviewStep = 0;
          _draftPreviewCarData = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _hasDraftSnapshot = true;
        _draftPreviewStep = restoredStep.clamp(0, _kSellStepCount - 1);
        _draftPreviewCarData = restoredCarData;
      });
    } catch (e, st) { logNonFatal(e, st); }
  }

  String _draftTitle(Map<String, dynamic> data) {
    final brand = (data['brand'] ?? '').toString().trim();
    final model = (data['model'] ?? '').toString().trim();
    final trim = (data['trim'] ?? '').toString().trim();
    final year = (data['year'] ?? '').toString().trim();
    final title = [brand, model].where((v) => v.isNotEmpty).join(' ');
    final suffix = [trim, year].where((v) => v.isNotEmpty).join(' • ');
    if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  Widget _buildDraftBanner() {
    if (!_hasDraftSnapshot || _hideDraftBanner) {
      return const SizedBox.shrink();
    }
    final labels = <String>[
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final stepLabel = labels[_draftPreviewStep.clamp(0, 4).toInt()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.drafts_outlined, color: Color(0xFFFF6B00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _trLegacyText(
                            context,
                            'Draft in progress',
                            ar: 'مسودة قيد التقدم',
                            ku: 'ڕەشنووسی لە پێشکەوتن',
                          ),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(stepLabel, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _draftTitle(_draftPreviewCarData ?? carData),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Continue here to finish the listing, or discard it if you want to start over.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _clearAllSellDrafts();
                        if (!mounted) return;
                        setState(() {
                          currentStep = 0;
                          carData = {};
                          completedSteps.clear();
                          _hasDraftSnapshot = false;
                          _draftPreviewStep = 0;
                          _draftPreviewCarData = null;
                          _sellPageResetToken++;
                        });
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(0);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard draft'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => unawaited(_resumeSellDraft()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    int controllerInitialPage = 0;
    final initialDraft = widget.initialDraftSnapshot;
    if (initialDraft != null) {
      controllerInitialPage =
          _readSellDraftStepDynamic(initialDraft['currentStep'])
              .clamp(0, _kSellStepCount - 1);
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
          final t = currentStep.clamp(0, _kSellStepCount - 1);
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
                  itemCount: _kSellStepCount,
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
    if (currentStep < _kSellStepCount - 1) {
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
    final clamped = index.clamp(0, _kSellStepCount - 1);
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

// Step 1: Basic Information (Brand, Model, Trim, Year)
