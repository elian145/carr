part of 'sell_flow.dart';

mixin _SellStep3Catalog on _SellStep3Fields {
  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController();
    _phoneController = TextEditingController();
    _descriptionController.text = '';
    _resetStep3();
    _hydrateFromParentCarData();
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
      contactPhone = data['contact_phone']?.toString();
      isQuickSell = data['is_quick_sell'] == true;
      selectedCurrency = (data['currency']?.toString().trim().isNotEmpty == true)
          ? data['currency'].toString()
          : selectedCurrency;
      _priceController.text = selectedPrice ?? '';
      _phoneController.text = (contactPhone ?? '').replaceFirst(RegExp(r'^\+964'), '');
      _descriptionController.text = data['description']?.toString() ?? '';
    });
  }

  void _syncStep3DraftToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['price'] = selectedPrice;
    parentState.carData['city'] = selectedCity;
    parentState.carData['plate_type'] = selectedPlateType;
    parentState.carData['plate_city'] = selectedPlateCity;
    parentState.carData['contact_phone'] = contactPhone;
    parentState.carData['description'] = _descriptionController.text.trim();
    parentState.carData['is_quick_sell'] = isQuickSell;
    parentState.carData['currency'] = selectedCurrency;
    parentState.setState(() {});
    unawaited(parentState._saveSellDraftSnapshot());
  }

  @override
  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _priceFocusNode.dispose();
    _priceController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _SellStep3Fields._draftKey,
        json.encode(<String, dynamic>{
          'selectedPrice': selectedPrice,
          'selectedCity': selectedCity,
          'selectedPlateType': selectedPlateType,
          'selectedPlateCity': selectedPlateCity,
          'contactPhone': contactPhone,
          'isQuickSell': isQuickSell,
          'isPriceManualInput': isPriceManualInput,
          'selectedCurrency': selectedCurrency,
          'priceControllerText': _priceController.text,
          'descriptionControllerText': _descriptionController.text,
        }),
      );
    } catch (e, st) { logNonFatal(e, st); }
  }

  void _resetStep3() {
    selectedPrice = null;
    selectedCity = null;
    selectedPlateType = null;
    selectedPlateCity = null;
    contactPhone = null;
    _descriptionController.clear();
    _phoneController.clear();
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

  // "All the cities we have" (keep in sync with Home filters list).
  final List<String> _plateCities = const [
    'Baghdad',
    'Basra',
    'Erbil',
    'Najaf',
    'Karbala',
    'Kirkuk',
    'Mosul',
    'Sulaymaniyah',
    'Dohuk',
    'Anbar',
    'Halabja',
    'Diyala',
    'Diyarbakir',
    'Maysan',
    'Muthanna',
    'Dhi Qar',
    'Salaheldeen',
  ];
}
