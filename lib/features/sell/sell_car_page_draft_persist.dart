part of 'sell_flow.dart';

mixin _SellCarPageDraftPersist on _SellCarPageFields {
  int _effectivePersistedDraftStep() {
    return currentStep.clamp(0, _SellCarPageFields._kSellStepCount - 1);
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

  /// Blocks dispose/async draft saves while create→upload is in flight.
  void _beginSubmitDraftHandoff() {
    _skipDraftPersistOnDispose = true;
    LegacySellDraftPrefs.invalidatePersist();
  }

  /// Create failed before a listing existed — allow draft saves again.
  void _abortSubmitDraftHandoff() {
    _skipDraftPersistOnDispose = false;
    LegacySellDraftPrefs.allowPersist();
  }

  /// Clears persisted draft storage after the listing exists.
  ///
  /// Intentionally leaves in-memory [carData] alone: wiping it mid-submit
  /// changes the Review step's [ValueKey] and Flutter recreates the page as an
  /// empty placeholder while upload is still running. Prefs +
  /// [_skipDraftPersistOnDispose] are enough to avoid a draft+listing pair if
  /// the process is killed; the sell route is disposed on navigate-away.
  Future<void> _clearSubmittedDraftOnly({String? draftId}) async {
    try {
      _skipDraftPersistOnDispose = true;
      LegacySellDraftPrefs.invalidatePersist();
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
          _hasDraftSnapshot = false;
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

  /// Clears active draft prefs + removes [draftId] from the archive when the
  /// in-memory draft no longer has meaningful content. Does NOT bump the
  /// persist epoch by itself (callers that need to kill in-flight saves must
  /// call [LegacySellDraftPrefs.invalidatePersist] first).
  Future<void> _purgeEmptyDraftFromStorage({
    required String draftId,
    required int epoch,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await LegacySellDraftPrefs.clearActiveStorage();
      final id = draftId.trim();
      if (id.isNotEmpty) {
        final archive =
            _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
        archive.removeWhere((item) => item['draftId']?.toString() == id);
        if (archive.isEmpty) {
          await sp.remove(_sellDraftArchiveKey);
        } else {
          await sp.setString(
            _sellDraftArchiveKey,
            _encodeSellDraftArchive(archive),
          );
        }
        // Disposable empty-draft media only — never while a pending
        // submission still needs the folder for upload/retry.
        final pending =
            await PendingSellSubmissionService.instance.peek(id);
        if (pending == null &&
            LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) {
          await SellDraftMediaPersistence.deleteLocalDraftFolder(id);
        }
      }
      if (mounted) {
        setState(() {
          _hasDraftSnapshot = false;
        });
      }
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Auto-discards a NEW-listing draft after the user deletes its last photo
  /// (and any other media) when no other meaningful fields remain. Never runs
  /// in edit-existing-listing mode.
  Future<void> _discardEmptyDraftAfterLastMediaRemoved() async {
    if (_isEditMode) return;
    if (sell_draft_helpers.carDataHasMeaningfulNonMediaContent(carData)) {
      return;
    }
    final draftId = _currentDraftId;
    try {
      _skipDraftPersistOnDispose = true;
      LegacySellDraftPrefs.invalidatePersist();
      // Never wipe media for a draft that already handed off to submission
      // (prefs discard alone is fine; folder delete is not).
      final pending =
          await PendingSellSubmissionService.instance.peek(draftId);
      await sell_draft_helpers.discardSellDraftById(draftId);
      await LegacySellDraftPrefs.clearActiveStepStorage();
      if (pending == null && draftId.trim().isNotEmpty) {
        await SellDraftMediaPersistence.deleteLocalDraftFolder(draftId);
      }
      if (!mounted) {
        LegacySellDraftPrefs.allowPersist();
        return;
      }
      setState(() {
        carData = <String, dynamic>{};
        _hasDraftSnapshot = false;
        _hideDraftBanner = true;
        _draftPreviewStep = 0;
        _draftPreviewCarData = null;
        _currentDraftId = _newSellDraftId();
        _sellPageResetToken++;
        _draftResumeToken++;
        currentStep = 0;
        completedSteps = <int>{};
      });
      try {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      } catch (e, st) {
        logNonFatal(e, st);
      }
    } catch (e, st) {
      logNonFatal(e, st);
    } finally {
      LegacySellDraftPrefs.allowPersist();
      _skipDraftPersistOnDispose = false;
    }
  }

  Future<void> _saveSellDraftSnapshot() async {
    if (_isEditMode) return;
    if (_skipDraftPersistOnDispose || LegacySellDraftPrefs.suppressPersist) {
      return;
    }
    // Resume-after-reopen fix (real-device evidence): once Submit has
    // durably recorded a `PendingSellSubmissionRecord` for this draftId,
    // that submission is no longer merely an ordinary editable draft (see
    // `PendingSellSubmissionService.hasCreatedListing`'s doc comment). An
    // in-flight submission's own draftId should not normally reach this
    // save path at all (the Sell entry points now skip re-offering it as a
    // continuable draft -- see `SellDraftGatePage`/`SellEntryRouterPage`),
    // but guard here too as defense-in-depth: never let a leftover
    // autosave silently resurrect/overwrite the ordinary draft snapshot
    // for a submission that is already being resumed elsewhere.
    if (_currentDraftId.isNotEmpty) {
      final pending =
          await PendingSellSubmissionService.instance.peek(_currentDraftId);
      if (pending != null) {
        appLog(
          '[SELL RESUME] draft save attempted for pending '
          'record=$_currentDraftId (status=${pending.status.name}); '
          'skipping ordinary draft persist',
        );
        return;
      }
    }
    final epoch = LegacySellDraftPrefs.persistEpoch;
    try {
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      if (!_hasMeaningfulDraftValue(carData)) {
        // Last-photo / empty-draft fix: previously, when a draft became
        // empty AFTER having a snapshot (e.g. user deleted the only photo
        // with no other fields), this path returned early and LEFT the
        // old snapshot intact -- so the deleted photo reappeared in My
        // Listings and last-photo deletion looked "blocked". Clear the
        // active snapshot + this draft's archive entry instead.
        await _purgeEmptyDraftFromStorage(
          draftId: _currentDraftId,
          epoch: epoch,
        );
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
          _mergePersistedCarData(storedCarData);
        });
      } else {
        _mergePersistedCarData(storedCarData);
      }
      final snapshot = <String, dynamic>{
        'draftId': _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
        'currentStep': persistedStep,
        'carData': _draftValue(carData),
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

  static const _kSellMediaKeys = <String>{
    'images',
    'original_images',
    'blurred_images',
    'damage_images',
    'original_damage_images',
    'blurred_damage_images',
    'videos',
    'processed_image_paths',
  };

  /// Copy persisted draft fields onto the live [carData] map without replacing
  /// it, and without wiping picker files when the copy-to-disk step dropped them.
  void _mergePersistedCarData(Map<String, dynamic> stored) {
    for (final entry in stored.entries) {
      if (_kSellMediaKeys.contains(entry.key)) {
        final persisted = entry.value;
        final live = carData[entry.key];
        final persistedEmpty = persisted is! List || persisted.isEmpty;
        final liveHas = live is List && live.isNotEmpty;
        // Don't wipe live picker files when durable copy dropped them.
        if (persistedEmpty && liveHas) continue;
        // Stale-save-after-delete: an older `prepareCarDataForStorage`
        // that started before the user cleared photos must not resurrect
        // those paths onto a live list that is now intentionally empty.
        final liveCleared = live is List && live.isEmpty;
        if (liveCleared && !persistedEmpty) continue;
        carData[entry.key] = persisted;
      } else {
        carData[entry.key] = entry.value;
      }
    }
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
    _openedWizardStep = currentStep;
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
      // User may have tapped Back before this async reconcile finished; do not
      // yank them away from an earlier step (e.g. photos).
      if (_openedWizardStep != null && currentStep != _openedWizardStep) {
        return;
      }
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
          includeMissingLocalPaths: true,
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

}
