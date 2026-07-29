part of 'sell_flow.dart';

mixin _SellCarPageDraftPersist on _SellCarPageFields {
  bool _sellPersistFieldNonEmpty(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is num) return true;
    if (v is bool) return v;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return v.toString().trim().isNotEmpty;
  }

  /// Highest wizard index that already has saved field data.
  /// Used so "Back" does not persist an earlier [currentStep] while later
  /// step fields remain in [carData].
  int _deepestSellWizardStepHintFromCarData() {
    final d = carData;
    int maxIdx = 0;
    if (_sellPersistFieldNonEmpty(d['brand']) ||
        _sellPersistFieldNonEmpty(d['model']) ||
        _sellPersistFieldNonEmpty(d['trim']) ||
        _sellPersistFieldNonEmpty(d['year'])) {
      maxIdx = 1;
    }
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
      maxIdx = math.max(maxIdx, 2);
    }
    if (_sellPersistFieldNonEmpty(d['price']) ||
        _sellPersistFieldNonEmpty(d['city']) ||
        _sellPersistFieldNonEmpty(d['contact_phone']) ||
        (d['contact_phones'] is List && (d['contact_phones'] as List).isNotEmpty) ||
        _sellPersistFieldNonEmpty(d['plate_type']) ||
        _sellPersistFieldNonEmpty(d['plate_city']) ||
        _sellPersistFieldNonEmpty(d['description'])) {
      maxIdx = math.max(maxIdx, SellWizardSteps.pricingContact);
    }
    if (d['use_blurred_plates'] is bool) {
      maxIdx = math.max(maxIdx, SellWizardSteps.plateBlur);
    }
    return maxIdx.clamp(0, _SellCarPageFields._kSellStepCount - 1);
  }

  int _effectivePersistedDraftStep() {
    return math
        .max(currentStep, _deepestSellWizardStepHintFromCarData())
        .clamp(0, _SellCarPageFields._kSellStepCount - 1);
  }

  void _dismissKeyboard() => _dismissAnyKeyboard(context);

  Future<void> _saveDraftCurrentStep() async {
    if (_isEditMode) return;
    if (_skipDraftPersistOnDispose || LegacySellDraftPrefs.suppressPersist) {
      return;
    }
    final epoch = LegacySellDraftPrefs.persistEpoch;
    try {
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await sp.setInt(_SellCarPageFields._draftCurrentStepKey, _effectivePersistedDraftStep());
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
      // Block step dispose / in-flight saves from resurrecting the draft.
      _skipDraftPersistOnDispose = true;
      LegacySellDraftPrefs.invalidatePersist();
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_SellCarPageFields._draftCurrentStepKey);
      await sp.remove(_SellCarPageFields._draftSnapshotKey);
      await sp.remove(_sellDraftArchiveKey);
      await LegacySellDraftPrefs.clearActiveStorage();
      if (mounted) {
        setState(() {
          carData = <String, dynamic>{};
          _hasDraftSnapshot = false;
          _draftPreviewStep = 0;
          _draftPreviewCarData = null;
          _hideDraftBanner = true;
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

      await sp.remove(_SellCarPageFields._draftCurrentStepKey);
      await sp.remove(_SellCarPageFields._draftSnapshotKey);
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
    return sell_draft_helpers.hasMeaningfulSellDraftValue(value);
  }

  Future<void> _saveSellDraftSnapshot() async {
    if (_isEditMode) return;
    if (_skipDraftPersistOnDispose || LegacySellDraftPrefs.suppressPersist) {
      return;
    }
    final epoch = LegacySellDraftPrefs.persistEpoch;
    try {
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      final hasExistingSnapshot =
          (sp.getString(_SellCarPageFields._draftSnapshotKey)?.trim().isNotEmpty == true);
      if (!_hasMeaningfulDraftValue(carData)) {
        if (hasExistingSnapshot) {
          if (mounted) {
            setState(() {
              _hasDraftSnapshot = true;
            });
          }
          return;
        }
        await sp.remove(_SellCarPageFields._draftCurrentStepKey);
        await sp.remove(_SellCarPageFields._draftSnapshotKey);
        await LegacySellDraftPrefs.clearActiveStepStorage();
        if (mounted) {
          setState(() {
            _hasDraftSnapshot = false;
          });
        }
        return;
      }
      final persistedStep = _effectivePersistedDraftStep();
      carData['sell_wizard_v2'] = true;
      final storedCarData =
          await SellDraftMediaPersistence.prepareCarDataForStorage(
        carData,
        draftId: _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
      );
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch) ||
          _skipDraftPersistOnDispose) {
        return;
      }
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
        _SellCarPageFields._draftSnapshotKey,
        json.encode(snapshot),
      );
      await sp.setInt(_SellCarPageFields._draftCurrentStepKey, persistedStep);
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
      archive.removeWhere((draft) => draft['draftId'] == _currentDraftId);
      archive.insert(0, snapshot);
      await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _restoreSellDraftSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_SellCarPageFields._draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final jsonStep = _readSellDraftStepDynamic(data['currentStep']);
      final prefsStep = sp.getInt(_SellCarPageFields._draftCurrentStepKey);
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
        await sp.remove(_SellCarPageFields._draftCurrentStepKey);
        await sp.remove(_SellCarPageFields._draftSnapshotKey);
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        final migratedStep = migrateSellWizardStep(restoredStep, restoredCarData);
        currentStep = migratedStep;
        carData = _resolveCarDataMedia(restoredCarData);
        carData['sell_wizard_v2'] = true;
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
      final prefsStep = sp.getInt(_SellCarPageFields._draftCurrentStepKey);
      int fromDisk = currentStep;
      final raw = sp.getString(_SellCarPageFields._draftSnapshotKey);
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
    for (final key in [
      'images',
      'original_images',
      'blurred_images',
      'damage_images',
      'original_damage_images',
      'blurred_damage_images',
      'videos',
    ]) {
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

    final migratedStep = migrateSellWizardStep(
      _readSellDraftStepDynamic(snapshot['currentStep']),
      restoredCarData,
    );
    if (restoreCurrentStep) {
      currentStep = migratedStep;
    }
    carData = _resolveCarDataMedia(restoredCarData);
    carData['sell_wizard_v2'] = true;
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
      final raw = sp.getString(_SellCarPageFields._draftSnapshotKey);
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
        await sp.remove(_SellCarPageFields._draftCurrentStepKey);
        await sp.remove(_SellCarPageFields._draftSnapshotKey);
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
        final previewData = Map<String, dynamic>.from(restoredCarData);
        _draftPreviewStep = migrateSellWizardStep(restoredStep, previewData);
        _draftPreviewCarData = previewData;
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
}
