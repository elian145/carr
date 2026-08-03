part of 'sell_flow.dart';

mixin _SellStep3Catalog on _SellStep3Fields {
  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController();
    _phoneControllers.add(TextEditingController());
    _descriptionController.text = '';
    _resetStep3();
    _hydrateFromParentCarData();
    _defaultContactPhoneFromUserIfEmpty();
  }

  List<String> _phonesFromCarData(Map<String, dynamic> data) {
    final rawList = data['contact_phones'];
    final out = <String>[];
    if (rawList is List) {
      for (final item in rawList) {
        final s = item.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    if (out.isEmpty) {
      final single = data['contact_phone']?.toString().trim() ?? '';
      if (single.isNotEmpty) out.add(single);
    }
    return out.take(_SellStep3Fields.maxContactPhones).toList();
  }

  /// Prefill the first contact phone with the signed-in account number.
  void _defaultContactPhoneFromUserIfEmpty() {
    if (contactPhones.isNotEmpty) return;
    final raw = (context.read<AuthService>().userPhone ?? '').trim();
    if (raw.isEmpty) return;
    final digits = _localPhoneDigits(raw);
    if (digits.isEmpty) return;
    final full = '+964$digits';
    contactPhones = <String>[full];
    contactPhone = full;
    _applyContactPhonesToControllers(contactPhones);
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['contact_phone'] = contactPhone;
    parentState.carData['contact_phones'] = List<String>.from(contactPhones);
  }

  void _hydrateFromParentCarData() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final data = parentState?.carData;
    if (data == null || data.isEmpty) return;
    setState(() {
      selectedPrice = data['price']?.toString();
      selectedCity = data['city']?.toString();
      selectedPlateType = data['plate_type']?.toString();
      selectedPlateCity = data['plate_city']?.toString();
      contactPhones = _phonesFromCarData(data);
      contactPhone = contactPhones.isEmpty ? null : contactPhones.first;
      isQuickSell = data['is_quick_sell'] == true;
      selectedCurrency = (data['currency']?.toString().trim().isNotEmpty == true)
          ? data['currency'].toString()
          : selectedCurrency;
      final rawPrice = selectedPrice ?? '';
      _priceController.text = ThousandsSeparatorInputFormatter.format(
        rawPrice.replaceAll(RegExp(r'[^\d.]'), ''),
      );
      _applyContactPhonesToControllers(contactPhones);
      _descriptionController.text = data['description']?.toString() ?? '';
    });
    final verified = data['contact_verified_phones'];
    if (verified is List && parentState != null) {
      for (final item in verified) {
        final digits = item
            .toString()
            .replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty) {
          parentState._verifiedListingPhones.add(digits);
        }
      }
    }
  }

  void _syncStep3DraftToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    contactPhones = _collectContactPhonesFromControllers();
    contactPhone = contactPhones.isEmpty ? null : contactPhones.first;
    parentState.carData['price'] = selectedPrice;
    parentState.carData['city'] = selectedCity;
    parentState.carData['plate_type'] = selectedPlateType;
    parentState.carData['plate_city'] = selectedPlateCity;
    parentState.carData['contact_phone'] = contactPhone;
    parentState.carData['contact_phones'] = List<String>.from(contactPhones);
    parentState.carData['description'] = _descriptionController.text.trim();
    parentState.carData['is_quick_sell'] = isQuickSell;
    parentState.carData['currency'] = selectedCurrency;
    parentState.setState(() {});
    unawaited(parentState._saveSellDraftSnapshot());
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _priceFocusNode.dispose();
    _priceController.dispose();
    for (final c in _phoneControllers) {
      c.dispose();
    }
    _phoneControllers.clear();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    try {
      if (LegacySellDraftPrefs.suppressPersist) return;
      final epoch = LegacySellDraftPrefs.persistEpoch;
      contactPhones = _collectContactPhonesFromControllers();
      contactPhone = contactPhones.isEmpty ? null : contactPhones.first;
      final sp = await SharedPreferences.getInstance();
      if (!LegacySellDraftPrefs.isCurrentPersistEpoch(epoch)) return;
      await sp.setString(
        _SellStep3Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedPrice': selectedPrice,
          'selectedCity': selectedCity,
          'selectedPlateType': selectedPlateType,
          'selectedPlateCity': selectedPlateCity,
          'contactPhone': contactPhone,
          'contactPhones': contactPhones,
          'isQuickSell': isQuickSell,
          'selectedCurrency': selectedCurrency,
          'priceControllerText': _priceController.text,
          'descriptionControllerText': _descriptionController.text,
        }),
      );
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  void _resetStep3() {
    selectedPrice = null;
    selectedCity = null;
    selectedPlateType = null;
    selectedPlateCity = null;
    contactPhone = null;
    contactPhones = <String>[];
    _descriptionController.clear();
    for (final c in _phoneControllers) {
      c.clear();
    }
    while (_phoneControllers.length > 1) {
      _phoneControllers.removeLast().dispose();
    }
    if (_phoneControllers.isEmpty) {
      _phoneControllers.add(TextEditingController());
    }
    isQuickSell = false;
    selectedCurrency = 'USD';
    _priceController.clear();
    // Initialize global currency symbol
    globalSymbol = r'$';
  }

  void _dismissKeyboard() {
    _dismissAnyKeyboard(context);
    _priceFocusNode.unfocus();
  }

  final List<String> cities = [
    'Baghdad',
    'Basra',
    'Mosul',
    'Erbil',
    'Najaf',
    'Karbala',
    'Sulaymaniyah',
    'Kirkuk',
    'Nasiriyah',
    'Amara',
    'Ramadi',
    'Fallujah',
    'Tikrit',
    'Samarra',
  ];

  final List<String> _plateTypeOptions = const [
    'private',
    'temporary',
    'commercial',
    'taxi',
  ];

  // Keep in sync with [kPlateCityFilterOptions].
  List<String> get _plateCities => kPlateCityFilterOptions;
}
