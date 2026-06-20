part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

extension SellPageDraft on _SellPageState {
  void _clearOnlineSpecOptionLists() {
    _engineSizeDisplayOptions = null;
    _cylinderOptions = null;
    _fuelEconomyOptions = null;
    _seatingOptions = null;
    _transmissionOptions = null;
    _drivetrainOptions = null;
    _bodyTypeOptions = null;
    _engineTypeOptions = null;
    _fuelTypeOptions = null;
    _onlineSpecVariants = null;
  }

  void _clearCatalogExtraFields() {
    _clearOnlineSpecOptionLists();
    _engineSizeCtl.clear();
    _cylinderCtl.clear();
    _fuelEconomyCtl.clear();
    _seatingCtl.clear();
  }

  String _buildDraftOwnerKey() {
    final user = AuthService().currentUser;
    final raw =
        (user?['public_id'] ??
                user?['id'] ??
                user?['username'] ??
                user?['email'] ??
                'guest')
            .toString()
            .trim();
    return raw.isEmpty ? 'guest' : raw;
  }

  String _normalizeChoice(
    dynamic raw,
    Iterable<String> allowed,
    String fallback,
  ) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return fallback;
    final normalized = value.toLowerCase().replaceAll('_', '-');
    for (final option in allowed) {
      if (option.toLowerCase() == normalized) return option;
    }
    return fallback;
  }

  String _normalizeCatalogValue(dynamic raw, Iterable<String> allowed) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return '';
    for (final option in allowed) {
      if (option.toLowerCase() == value.toLowerCase()) return option;
    }
    return '';
  }

  Map<String, dynamic> _draftFromRouteSnapshot(Map<String, dynamic> snapshot) {
    final rawCarData = snapshot['carData'];
    final data = rawCarData is Map
        ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
        : Map<String, dynamic>.from(snapshot);

    final editId = (data['_editListingId'] ?? data['id'] ?? data['carId'] ?? '')
        .toString()
        .trim();
    if (editId.isNotEmpty &&
        (widget.editListing || snapshot['isEditMode'] == true)) {
      data['_editListingId'] = editId;
    }

    if (data['image_paths'] == null && data['images'] is List) {
      data['image_paths'] = data['images'];
    }
    if (data['video_paths'] == null && data['videos'] is List) {
      data['video_paths'] = data['videos'];
    }
    if (data['damage_image_paths'] == null && data['damage_images'] is List) {
      data['damage_image_paths'] = data['damage_images'];
    }
    data['complete'] ??= snapshot['currentStep'] == 4;
    data['updated_at'] ??= DateTime.now().toIso8601String();
    return data;
  }

  Future<void> _startFreshFromRoute() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    await SellDraftPrefs.beginFreshListing();
    await SellDraftPrefs.clearListingDraft(owner);
    SellDraftPrefs.allowPersist(); // step scratch only; archive untouched
    if (!mounted) return;
    setState(() {
      _editListingId = null;
      _draftLoaded = true;
      _draftExists = false;
      _draftIsComplete = false;
      _draftPreviewData = null;
      _images.clear();
      _videos.clear();
      _damageImages.clear();
    });
  }

  Future<void> _loadInitialDraftSnapshot(Map<String, dynamic> snapshot) async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final draft = _draftFromRouteSnapshot(snapshot);
    if (!_hasMeaningfulDraftData(draft)) {
      await _loadDraftPreview();
      return;
    }
    await SellDraftPrefs.saveListingDraft(owner, draft);
    if (!mounted) return;
    final editId = (draft['_editListingId'] ?? '').toString().trim();
    setState(() {
      _editListingId = editId.isEmpty ? null : editId;
      _draftLoaded = true;
      _draftExists = true;
      _draftIsComplete = draft['complete'] == true;
      _draftPreviewData = draft;
    });
    await _restoreDraft();
  }

  void _onDraftFieldChanged() {
    _scheduleDraftSave();
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

  bool _hasMeaningfulDraftData(Map<String, dynamic> data) {
    return (data['brand'] ?? '').toString().trim().isNotEmpty ||
        (data['model'] ?? '').toString().trim().isNotEmpty ||
        (data['trim'] ?? '').toString().trim().isNotEmpty ||
        (data['year'] ?? '').toString().trim().isNotEmpty ||
        (data['mileage'] ?? '').toString().trim().isNotEmpty ||
        (data['price'] ?? '').toString().trim().isNotEmpty ||
        (data['location'] ?? '').toString().trim().isNotEmpty ||
        (data['description'] ?? '').toString().trim().isNotEmpty ||
        (data['engine_size'] ?? '').toString().trim().isNotEmpty ||
        (data['cylinder_count'] ?? '').toString().trim().isNotEmpty ||
        (data['fuel_economy'] ?? '').toString().trim().isNotEmpty ||
        (data['seating'] ?? '').toString().trim().isNotEmpty ||
        (data['image_paths'] is List &&
            (data['image_paths'] as List).isNotEmpty) ||
        (data['video_paths'] is List &&
            (data['video_paths'] as List).isNotEmpty) ||
        (data['engine_type'] ?? 'gasoline') != 'gasoline' ||
        (data['fuel_type'] ?? 'gasoline') != 'gasoline' ||
        (data['transmission'] ?? 'automatic') != 'automatic' ||
        (data['drive_type'] ?? 'fwd') != 'fwd' ||
        (data['condition'] ?? 'used') != 'used' ||
        (data['body_type'] ?? 'sedan') != 'sedan' ||
        (data['currency'] ?? 'USD') != 'USD' ||
        (data['title_status'] ?? 'clean').toString().toLowerCase() != 'clean' ||
        (data['damage_image_paths'] is List &&
            (data['damage_image_paths'] as List).isNotEmpty) ||
        (data['vin'] ?? '').toString().trim().isNotEmpty;
  }

  Future<void> _loadDraftPreview() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final draft = await SellDraftPrefs.loadListingDraft(owner);
    if (!mounted) return;
    if (draft == null || !_hasMeaningfulDraftData(draft)) {
      setState(() {
        _draftLoaded = true;
        _draftExists = false;
        _draftIsComplete = false;
        _draftPreviewData = null;
      });
      return;
    }
    setState(() {
      _draftLoaded = true;
      _draftExists = true;
      _draftIsComplete = draft['complete'] == true;
      _draftPreviewData = draft;
    });
  }

  bool _hasMeaningfulDraftContent() {
    if (_selectedBrand?.trim().isNotEmpty == true) return true;
    if (_selectedModel?.trim().isNotEmpty == true) return true;
    if (_selectedTrim?.trim().isNotEmpty == true) return true;
    if (_year.text.trim().isNotEmpty) return true;
    if (_mileage.text.trim().isNotEmpty) return true;
    if (_price.text.trim().isNotEmpty) return true;
    if (_location.text.trim().isNotEmpty) return true;
    if (_description.text.trim().isNotEmpty) return true;
    if (_engineSizeCtl.text.trim().isNotEmpty) return true;
    if (_cylinderCtl.text.trim().isNotEmpty) return true;
    if (_fuelEconomyCtl.text.trim().isNotEmpty) return true;
    if (_seatingCtl.text.trim().isNotEmpty) return true;
    if (_engineType != 'gasoline') return true;
    if (_fuelType != 'gasoline') return true;
    if (_transmission != 'automatic') return true;
    if (_driveType != 'fwd') return true;
    if (_condition != 'used') return true;
    if (_bodyType != 'sedan') return true;
    if (_currency != 'USD') return true;
    if (_titleStatus != 'clean') return true;
    if (_damagedParts.text.trim().isNotEmpty) return true;
    if (_vin.text.trim().isNotEmpty) return true;
    return _images.isNotEmpty || _videos.isNotEmpty || _damageImages.isNotEmpty;
  }

  bool _isListingComplete() {
    final brand = _selectedBrand?.trim() ?? '';
    final model = _selectedModel?.trim() ?? '';
    final trim = _selectedTrim?.trim() ?? '';
    final year = int.tryParse(_year.text.trim());
    final mileage = int.tryParse(_mileage.text.trim());
    final price = double.tryParse(_price.text.trim());
    final location = _location.text.trim();
    return brand.isNotEmpty &&
        model.isNotEmpty &&
        trim.isNotEmpty &&
        year != null &&
        year >= 1980 &&
        year <= DateTime.now().year + 1 &&
        mileage != null &&
        mileage >= 0 &&
        price != null &&
        price > 0 &&
        location.isNotEmpty;
  }

  Map<String, dynamic> _buildDraftData() {
    return <String, dynamic>{
      if ((_editListingId ?? '').trim().isNotEmpty)
        '_editListingId': _editListingId!.trim(),
      'brand': _selectedBrand,
      'model': _selectedModel,
      'trim': _selectedTrim,
      'year': _year.text.trim(),
      'mileage': _mileage.text.trim(),
      'price': _price.text.trim(),
      'currency': _currency,
      'location': _location.text.trim(),
      'description': _description.text.trim(),
      'engine_type': _engineType,
      'fuel_type': _fuelType,
      'transmission': _transmission,
      'drive_type': _driveType,
      'condition': _condition,
      'body_type': _bodyType,
      'engine_size': _engineSizeCtl.text.trim(),
      'cylinder_count': _cylinderCtl.text.trim(),
      'fuel_economy': _fuelEconomyCtl.text.trim(),
      'seating': _seatingCtl.text.trim(),
      'dataset_model_id': _datasetModelId,
      'catalog_year': _catalogYear,
      'image_paths': _images.map((file) => file.path).toList(),
      'video_paths': _videos.map((file) => file.path).toList(),
      'title_status': _titleStatus,
      'damaged_parts': _damagedParts.text.trim(),
      'damage_image_paths': _damageImages.map((file) => file.path).toList(),
      'vin': _vin.text.trim(),
      'complete': _isListingComplete(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  void _scheduleDraftSave({bool immediate = false}) {
    if (_restoringDraft || _submitting) return;
    _draftSaveTimer?.cancel();
    final delay = immediate ? Duration.zero : const Duration(milliseconds: 350);
    _draftSaveTimer = Timer(delay, () {
      if (!mounted || _restoringDraft || _submitting) return;
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft({bool immediate = false}) async {
    if (_restoringDraft || _submitting) return;
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final hasContent = _hasMeaningfulDraftContent();
    if (!hasContent) {
      await SellDraftPrefs.clearListingDraft(owner);
      if (mounted) {
        setState(() {
          _draftExists = false;
          _draftIsComplete = false;
          _draftLoaded = true;
        });
      }
      return;
    }

    var draft = _buildDraftData();
    draft = await SellDraftMediaPersistence.augmentDraftMap(
      draft,
      draftId: owner,
    );
    await SellDraftPrefs.saveListingDraft(owner, draft);
    if (!mounted) return;
    setState(() {
      _images
        ..clear()
        ..addAll(
          SellDraftMediaPersistence.resolvePathList(
            draft['image_paths'] is List
                ? List<dynamic>.from(draft['image_paths'] as List)
                : null,
          ).map((path) => XFile(path)),
        );
      _damageImages
        ..clear()
        ..addAll(
          SellDraftMediaPersistence.resolvePathList(
            draft['damage_image_paths'] is List
                ? List<dynamic>.from(draft['damage_image_paths'] as List)
                : null,
          ).map((path) => XFile(path)),
        );
      _videos
        ..clear()
        ..addAll(
          SellDraftMediaPersistence.resolvePathList(
            draft['video_paths'] is List
                ? List<dynamic>.from(draft['video_paths'] as List)
                : null,
          ).map((path) => XFile(path)),
        );
      _draftExists = true;
      _draftIsComplete = draft['complete'] == true;
      _draftLoaded = true;
      _draftPreviewData = draft;
    });
  }

  Future<void> _restoreDraft() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final draft = await SellDraftPrefs.loadListingDraft(owner);
    if (!mounted) return;
    if (draft == null) {
      setState(() {
        _draftLoaded = true;
        _draftExists = false;
        _draftIsComplete = false;
        _editListingId = null;
      });
      return;
    }

    _restoringDraft = true;
    try {
      final imagePaths = SellDraftMediaPersistence.resolvePathList(
        draft['image_paths'] is List
            ? List<dynamic>.from(draft['image_paths'] as List)
            : null,
      );
      final videoPaths = SellDraftMediaPersistence.resolvePathList(
        draft['video_paths'] is List
            ? List<dynamic>.from(draft['video_paths'] as List)
            : null,
      );
      final damageImagePaths = SellDraftMediaPersistence.resolvePathList(
        draft['damage_image_paths'] is List
            ? List<dynamic>.from(draft['damage_image_paths'] as List)
            : null,
      );

      final draftTitleStatus = (draft['title_status'] ?? 'clean')
          .toString()
          .toLowerCase();
      final normalizedTitle = draftTitleStatus == 'damaged'
          ? 'damaged'
          : 'clean';
      final brand = _normalizeCatalogValue(draft['brand'], CarCatalog.brands);
      final model = brand.isEmpty
          ? ''
          : _normalizeCatalogValue(
              draft['model'],
              CarCatalog.models[brand] ?? const <String>[],
            );
      final trim = (brand.isEmpty || model.isEmpty)
          ? ''
          : _normalizeCatalogValue(
              draft['trim'],
              CarCatalog.trimsFor(brand, model),
            );

      final loadedDraft = <String, dynamic>{
        'brand': brand,
        'model': model,
        'trim': trim,
        'year': (draft['year'] ?? '').toString().trim(),
        'mileage': (draft['mileage'] ?? '').toString().trim(),
        'price': (draft['price'] ?? '').toString().trim(),
        'currency': _normalizeChoice(draft['currency'], const [
          'USD',
          'IQD',
        ], 'USD'),
        'location': (draft['location'] ?? '').toString().trim(),
        'description': (draft['description'] ?? '').toString().trim(),
        'engine_type': _normalizeChoice(
          draft['engine_type'] ?? draft['fuel_type'],
          const ['gasoline', 'diesel', 'hybrid', 'electric'],
          'gasoline',
        ),
        'fuel_type': _normalizeChoice(
          draft['fuel_type'] ?? draft['engine_type'],
          const ['gasoline', 'diesel', 'hybrid', 'electric'],
          'gasoline',
        ),
        'transmission': _normalizeChoice(draft['transmission'], const [
          'automatic',
          'manual',
          'cvt',
          'semi-automatic',
        ], 'automatic'),
        'drive_type': _normalizeChoice(draft['drive_type'], const [
          'fwd',
          'rwd',
          'awd',
          '4wd',
        ], 'fwd'),
        'condition': _normalizeChoice(draft['condition'], const [
          'new',
          'used',
        ], 'used'),
        'body_type': _normalizeChoice(draft['body_type'], const [
          'sedan',
          'suv',
          'hatchback',
          'coupe',
          'pickup',
          'van',
          'convertible',
          'wagon',
        ], 'sedan'),
        'engine_size': (draft['engine_size'] ?? '').toString().trim(),
        'cylinder_count': (draft['cylinder_count'] ?? '').toString().trim(),
        'fuel_economy': (draft['fuel_economy'] ?? '').toString().trim(),
        'seating': (draft['seating'] ?? '').toString().trim(),
        'image_paths': imagePaths,
        'video_paths': videoPaths,
        'title_status': normalizedTitle,
        'damaged_parts': (draft['damaged_parts'] ?? '').toString().trim(),
        'damage_image_paths': damageImagePaths,
        'vin': (draft['vin'] ?? '').toString().trim(),
      };
      final editId = (draft['_editListingId'] ?? '').toString().trim();
      final hasMeaningfulContent =
          loadedDraft.entries.any((entry) {
            final value = entry.value;
            if (value is String) return value.trim().isNotEmpty;
            if (value is List) return value.isNotEmpty;
            return value != null;
          }) &&
          (loadedDraft['brand'].toString().isNotEmpty ||
              loadedDraft['model'].toString().isNotEmpty ||
              loadedDraft['trim'].toString().isNotEmpty ||
              loadedDraft['year'].toString().isNotEmpty ||
              loadedDraft['mileage'].toString().isNotEmpty ||
              loadedDraft['price'].toString().isNotEmpty ||
              loadedDraft['location'].toString().isNotEmpty ||
              loadedDraft['description'].toString().isNotEmpty ||
              loadedDraft['engine_size'].toString().isNotEmpty ||
              loadedDraft['cylinder_count'].toString().isNotEmpty ||
              loadedDraft['fuel_economy'].toString().isNotEmpty ||
              loadedDraft['seating'].toString().isNotEmpty ||
              imagePaths.isNotEmpty ||
              videoPaths.isNotEmpty ||
              loadedDraft['engine_type'] != 'gasoline' ||
              loadedDraft['fuel_type'] != 'gasoline' ||
              loadedDraft['transmission'] != 'automatic' ||
              loadedDraft['drive_type'] != 'fwd' ||
              loadedDraft['condition'] != 'used' ||
              loadedDraft['body_type'] != 'sedan' ||
              loadedDraft['currency'] != 'USD' ||
              loadedDraft['title_status'] != 'clean' ||
              loadedDraft['damaged_parts'].toString().trim().isNotEmpty ||
              damageImagePaths.isNotEmpty ||
              loadedDraft['vin'].toString().trim().isNotEmpty);
      if (!hasMeaningfulContent) {
        await SellDraftPrefs.clearListingDraft(owner);
        if (!mounted) return;
        setState(() {
          _draftLoaded = true;
          _draftExists = false;
          _draftIsComplete = false;
          _editListingId = null;
        });
        return;
      }

      setState(() {
        _selectedBrand = loadedDraft['brand'].toString().isEmpty
            ? null
            : loadedDraft['brand'].toString().trim();
        _selectedModel = loadedDraft['model'].toString().isEmpty
            ? null
            : loadedDraft['model'].toString().trim();
        _selectedTrim = loadedDraft['trim'].toString().isEmpty
            ? null
            : loadedDraft['trim'].toString().trim();
        _year.text = loadedDraft['year'];
        _mileage.text = loadedDraft['mileage'];
        _price.text = loadedDraft['price'];
        _currency = loadedDraft['currency'];
        _location.text = loadedDraft['location'];
        _description.text = loadedDraft['description'];
        _engineType = loadedDraft['engine_type'];
        _fuelType = loadedDraft['fuel_type'];
        _transmission = loadedDraft['transmission'];
        _driveType = loadedDraft['drive_type'];
        _condition = loadedDraft['condition'];
        _bodyType = loadedDraft['body_type'];
        _engineSizeCtl.text = loadedDraft['engine_size'];
        _cylinderCtl.text = loadedDraft['cylinder_count'];
        _fuelEconomyCtl.text = loadedDraft['fuel_economy'];
        _seatingCtl.text = loadedDraft['seating'];
        _titleStatus = loadedDraft['title_status'] as String;
        _damagedParts.text = loadedDraft['damaged_parts'] as String;
        _vin.text = loadedDraft['vin'] as String;
        _catalogYear = int.tryParse((draft['catalog_year'] ?? '').toString());
        _datasetModelId = int.tryParse(
          (draft['dataset_model_id'] ?? '').toString(),
        );
        _images
          ..clear()
          ..addAll(imagePaths.map((path) => XFile(path)));
        _damageImages
          ..clear()
          ..addAll(damageImagePaths.map((path) => XFile(path)));
        _videos
          ..clear()
          ..addAll(videoPaths.map((path) => XFile(path)));
        _draftExists = true;
        _draftIsComplete = draft['complete'] == true || _isListingComplete();
        _draftLoaded = true;
        _draftPreviewData = draft;
        _editListingId = editId.isEmpty ? null : editId;
      });
      _scheduleRefreshDataset();
    } finally {
      _restoringDraft = false;
    }
  }

  Future<void> _resumeDraft() async {
    await _restoreDraft();
  }

  Future<void> _discardDraft() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    _draftSaveTimer?.cancel();
    _restoringDraft = true;
    try {
      await SellDraftPrefs.clearListingDraft(owner);
      if (!mounted) return;
      setState(() {
        _selectedBrand = null;
        _selectedModel = null;
        _selectedTrim = null;
        _datasetModelId = null;
        _catalogYear = null;
        _year.clear();
        _mileage.clear();
        _price.clear();
        _location.clear();
        _description.clear();
        _engineSizeCtl.clear();
        _cylinderCtl.clear();
        _fuelEconomyCtl.clear();
        _seatingCtl.clear();
        _engineType = 'gasoline';
        _fuelType = 'gasoline';
        _transmission = 'automatic';
        _driveType = 'fwd';
        _condition = 'used';
        _bodyType = 'sedan';
        _currency = 'USD';
        _titleStatus = 'clean';
        _damagedParts.clear();
        _vin.clear();
        _images.clear();
        _videos.clear();
        _damageImages.clear();
        _clearOnlineSpecOptionLists();
        _draftExists = false;
        _draftIsComplete = false;
        _draftLoaded = true;
        _editListingId = null;
      });
    } finally {
      _restoringDraft = false;
      _scheduleRefreshDataset();
    }
  }

}
