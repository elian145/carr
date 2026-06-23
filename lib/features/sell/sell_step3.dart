part of 'sell_flow.dart';
class SellStep3Page extends StatefulWidget {
  const SellStep3Page({super.key});

  @override
  State<SellStep3Page> createState() => _SellStep3PageState();
}

class _SellStep3PageState extends State<SellStep3Page> {
  static const String _pricePickerNoneOption = 'none';
  static const String _draftKey = 'legacy_sell_draft_step3_v1';

  final _formKey = GlobalKey<FormState>();
  String? selectedPrice;
  String? selectedCity;
  String? selectedPlateType;
  String? selectedPlateCity;
  String? contactPhone;
  bool isQuickSell = false;
  bool isPriceManualInput = false;
  String selectedCurrency = 'USD';

  // Focus node for keyboard management
  final FocusNode _priceFocusNode = FocusNode();

  // Controller for price input
  late TextEditingController _priceController;
  late TextEditingController _phoneController;
  final TextEditingController _descriptionController =
      TextEditingController();

  // Currency conversion method
  String _convertCurrency(
    String price,
    String fromCurrency,
    String toCurrency,
  ) {
    if (price.isEmpty) return price;

    // Extract numeric value from price string
    String numericValue = price.replaceAll(RegExp(r'[^\d.]'), '');
    double value = double.tryParse(numericValue) ?? 0;

    if (value == 0) return price;

    double convertedValue;

    if (fromCurrency == 'USD' && toCurrency == 'IQD') {
      // Convert USD to IQD: 1 USD = 1420 IQD
      convertedValue = value * 1420;
    } else if (fromCurrency == 'IQD' && toCurrency == 'USD') {
      // Convert IQD to USD: 1 IQD = 1/1420 USD
      convertedValue = value / 1420;
    } else {
      // Same currency, no conversion needed
      return price;
    }

    // Format the converted value
    if (toCurrency == 'IQD') {
      return 'IQD ${convertedValue.toStringAsFixed(0)}';
    } else {
      return '\$${convertedValue.toStringAsFixed(0)}';
    }
  }

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
        _draftKey,
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

  Future<String?> _pickFromList(String title, List<String> options) async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 420,
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 420,
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (context, index) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final value = options[index];
                      final rawLower = value.trim().toLowerCase();
                      final displayValue = const {
                        'private',
                        'commercial',
                        'comercial',
                        'taxi',
                        'government',
                        'temporary',
                        'diplomatic',
                        'police',
                      }.contains(rawLower)
                          ? _translatePlateTypeLegacy(context, value)
                          : isValidCarRegionSpecCode(rawLower)
                          ? carRegionSpecDisplayLabelLocalized(context, rawLower)
                          : (_translateValueGlobal(context, value) ?? value);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, value),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.06),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayValue,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.white70),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.pricingContactTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _trLegacyText(
                      context,
                      'Set your price and contact information',
                      ar: 'حدد السعر ومعلومات التواصل',
                      ku: 'نرخ و زانیاری پەیوەندی دابنێ',
                    ),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Price (Modal or Manual Input)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: isPriceManualInput
                          ? TextFormField(
                              focusNode: _priceFocusNode,
                              controller: _priceController,
                              decoration: InputDecoration(
                                labelText: _trLegacyText(
                                  context,
                                  'Price (optional)',
                                  ar: 'السعر (اختياري)',
                                  ku: 'نرخ (ئیختیاری)',
                                ),
                                hintText: _trLegacyText(
                                  context,
                                  'Enter price',
                                  ar: 'أدخل السعر',
                                  ku: 'نرخ بنووسە',
                                ),
                                prefixText: selectedCurrency == 'IQD'
                                    ? 'IQD '
                                    : '\$',
                                prefixStyle: TextStyle(
                                  color: Color(0xFFFF6B00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                filled: true,
                                fillColor: _sellFlowManualFieldFill(context),
                                labelStyle: _sellFlowManualFieldLabelStyle(
                                  context,
                                ),
                                hintStyle: _sellFlowManualFieldHintStyle(
                                  context,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.red),
                                ),
                              ),
                              style: _sellFlowManualFieldTextStyle(context),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _dismissKeyboard(),
                              onTapOutside: (_) => _dismissKeyboard(),
                              inputFormatters: [
                                services.FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                setState(() {
                                  // Store the full price with currency prefix
                                  selectedPrice = value.isEmpty
                                      ? null
                                      : (selectedCurrency == 'IQD'
                                            ? 'IQD $value'
                                            : '\$$value');
                                });
                                _syncStep3DraftToParent();
                              },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null;
                                }
                                final price = int.tryParse(value.trim());
                                if (price == null) {
                                  return _trLegacyText(
                                    context,
                                    'Invalid price',
                                    ar: 'سعر غير صالح',
                                    ku: 'نرخی نادروست',
                                  );
                                }
                                if (price < 0) {
                                  return _trLegacyText(
                                    context,
                                    'Price cannot be negative',
                                    ar: 'لا يمكن أن يكون السعر سالبا',
                                    ku: 'نرخ ناتوانێت سالب بێت',
                                  );
                                }
                                return null;
                              },
                            )
                          : FormField<String>(
                              validator: (_) => null,
                              builder: (state) => GestureDetector(
                                onTap: () async {
                                  final List<String> numericOptions =
                                      selectedCurrency == 'IQD'
                                      ? [
                                          ...List.generate(
                                            200,
                                            (i) => (500000 + i * 500000)
                                                .toString(),
                                          ),
                                          ...List.generate(
                                            100,
                                            (i) =>
                                                (100000000 + (i + 1) * 1000000)
                                                    .toString(),
                                          ),
                                        ].map((p) => 'IQD $p').toList()
                                      : [
                                          ...List.generate(
                                            600,
                                            (i) => (500 + i * 500).toString(),
                                          ),
                                          ...List.generate(
                                            171,
                                            (i) => (300000 + (i + 1) * 10000)
                                                .toString(),
                                          ),
                                        ].map((p) => '\$$p').toList();
                                  final priceOptions = <String>[
                                    _pricePickerNoneOption,
                                    ...numericOptions,
                                  ];
                                  final choice = await _pickFromList(
                                    _trLegacyText(
                                      context,
                                      'Price ($selectedCurrency) (optional)',
                                      ar: 'السعر ($selectedCurrency) (اختياري)',
                                      ku:
                                          'نرخ ($selectedCurrency) (ئیختیاری)',
                                    ),
                                    priceOptions,
                                  );
                                  if (choice != null) {
                                    setState(() {
                                      selectedPrice =
                                          choice == _pricePickerNoneOption
                                          ? null
                                          : choice;
                                    });
                                    _syncStep3DraftToParent();
                                  }
                                },
                                child: buildFancySelector(
                                  context,
                                  currency: selectedCurrency,
                                  label: _trLegacyText(
                                    context,
                                    'Price ($selectedCurrency) (optional)',
                                    ar: 'السعر ($selectedCurrency) (اختياري)',
                                    ku:
                                        'نرخ ($selectedCurrency) (ئیختیاری)',
                                  ),
                                  value: selectedPrice != null
                                      ? _formatCurrencyGlobal(
                                          context,
                                          selectedPrice,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                    ),
                    SizedBox(width: 8),
                    // Currency Selector button (styled like pencil button)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          // Convert price when switching currency
                          if (selectedPrice != null &&
                              selectedPrice!.isNotEmpty) {
                            String convertedPrice = _convertCurrency(
                              selectedPrice!,
                              selectedCurrency,
                              selectedCurrency == 'USD' ? 'IQD' : 'USD',
                            );
                            selectedPrice = convertedPrice;
                            // Update controller with numeric value only
                            String numericValue = convertedPrice.replaceAll(
                              RegExp(r'[^\d.]'),
                              '',
                            );
                            _priceController.text = numericValue;
                          }
                          selectedCurrency = selectedCurrency == 'USD'
                              ? 'IQD'
                              : 'USD';
                          // Update global currency symbol
                          globalSymbol = selectedCurrency == 'IQD'
                              ? 'IQD '
                              : r'$';
                        });
                        _syncStep3DraftToParent();
                      },
                      icon: Text(
                        selectedCurrency,
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      tooltip:
                          _trLegacyText(
                            context,
                            'Switch to ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                            ar:
                                'التبديل إلى ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                            ku:
                                'گۆڕین بۆ ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                          ),
                    ),
                    SizedBox(width: 8),
                    // Pencil/Checkmark button
                    IconButton(
                      onPressed: () {
                        if (isPriceManualInput) {
                          // If in manual input mode, confirm the price and dismiss keyboard
                          _priceFocusNode.unfocus();
                          FocusScope.of(context).unfocus();
                          setState(() {
                            isPriceManualInput = false;
                            // Ensure the selectedPrice is properly formatted
                            if (_priceController.text.isNotEmpty) {
                              final numericValue = _priceController.text;
                              selectedPrice = selectedCurrency == 'IQD'
                                  ? 'IQD $numericValue'
                                  : '\$$numericValue';
                            } else {
                              selectedPrice = null;
                            }
                          });
                          _syncStep3DraftToParent();
                        } else {
                          // If in dropdown mode, switch to manual input
                          setState(() {
                            isPriceManualInput = true;
                            // Clear the controller to start fresh
                            _priceController.clear();
                            selectedPrice = null;
                          });
                          _syncStep3DraftToParent();
                        }
                      },
                      icon: Icon(
                        isPriceManualInput ? Icons.check : Icons.edit,
                        color: Color(0xFFFF6B00),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      tooltip: isPriceManualInput
                          ? AppLocalizations.of(context)!.confirmYear
                          : AppLocalizations.of(context)!.typeManually,
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),

            // City (Modal)
            FormField<String>(
              validator: (_) =>
                  selectedCity == null
                      ? _trLegacyText(
                          context,
                          'Please select city',
                          ar: 'يرجى اختيار المدينة',
                          ku: 'تکایە شار هەڵبژێرە',
                        )
                      : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.cityLabel,
                    cities,
                  );
                  if (choice != null) {
                    setState(() => selectedCity = choice);
                    _syncStep3DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.location_city,
                  label: '${AppLocalizations.of(context)!.cityLabel} *',
                  value: _translateValueGlobal(context, selectedCity),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Plate Type (Optional)
            GestureDetector(
              onTap: () async {
                _dismissKeyboard();
                final choice = await _pickFromList(
                  _trLegacyText(
                    context,
                    'Plate type',
                    ar: 'نوع اللوحة',
                    ku: 'جۆری پڵەیت',
                  ),
                  _plateTypeOptions.map(prettyTitleCase).toList(),
                );
                if (choice != null) {
                  setState(() {
                    selectedPlateType = choice.toLowerCase();
                  });
                  _syncStep3DraftToParent();
                }
              },
              child: buildFancySelector(
                context,
                icon: Icons.confirmation_number_outlined,
                label: _trLegacyText(
                  context,
                  'Plate type',
                  ar: 'نوع اللوحة',
                  ku: 'جۆری پڵەیت',
                ),
                value: selectedPlateType == null
                    ? null
                    : _translatePlateTypeLegacy(context, selectedPlateType!),
              ),
            ),
            SizedBox(height: 16),

            // Plate City (Optional)
            GestureDetector(
              onTap: () async {
                _dismissKeyboard();
                final choice = await _pickFromList(
                  _trLegacyText(
                    context,
                    'Plate city',
                    ar: 'مدينة اللوحة',
                    ku: 'شاری پڵەیت',
                  ),
                  _plateCities,
                );
                if (choice != null) {
                  setState(() => selectedPlateCity = choice);
                  _syncStep3DraftToParent();
                }
              },
              child: buildFancySelector(
                context,
                icon: Icons.location_on_outlined,
                label: _trLegacyText(
                  context,
                  'Plate city',
                  ar: 'مدينة اللوحة',
                  ku: 'شاری پڵەیت',
                ),
                value: selectedPlateCity == null
                    ? null
                    : (_translateValueGlobal(context, selectedPlateCity) ??
                        selectedPlateCity),
              ),
            ),
            SizedBox(height: 16),

            // Contact Phone
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: _trLegacyText(
                  context,
                  'WhatsApp/Phone Number *',
                  ar: 'رقم واتساب/الهاتف *',
                  ku: 'ژمارەی واتساپ/مۆبایل *',
                ),
                hintText: '7XX XXX XXXX',
                filled: true,
                fillColor: _sellFlowManualFieldFill(context),
                labelStyle: _sellFlowManualFieldLabelStyle(context),
                hintStyle: _sellFlowManualFieldHintStyle(context),
                prefixText: '+964 ',
                prefixStyle: TextStyle(
                  color: Color(0xFFFF6B00),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.phone, color: Color(0xFFFF6B00)),
              ),
              style: _sellFlowManualFieldTextStyle(context),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                services.LengthLimitingTextInputFormatter(10),
              ],
              onChanged: (value) {
                setState(() => contactPhone = '+964$value');
                _syncStep3DraftToParent();
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _trLegacyText(
                    context,
                    'Please enter phone number',
                    ar: 'يرجى إدخال رقم الهاتف',
                    ku: 'تکایە ژمارەی مۆبایل بنووسە',
                  );
                }
                if (value.trim().length < 10) {
                  return _trLegacyText(
                    context,
                    'Please enter a valid phone number',
                    ar: 'يرجى إدخال رقم هاتف صحيح',
                    ku: 'تکایە ژمارەی دروست بنووسە',
                  );
                }
                return null;
              },
            ),
            SizedBox(height: 24),

            // Listing Description (Optional)
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context)?.descriptionOptionalLabel ??
                    'Description (optional)',
                hintText:
                    _trLegacyText(
                      context,
                      'Add details about the car, condition, features, or notes',
                      ar: 'أضف تفاصيل عن السيارة والحالة والمزايا أو ملاحظات',
                      ku: 'وردەکاری دەربارەی ئۆتۆمبێلەکە، دۆخ، تایبەتمەندیەکان یان تێبینی زیاد بکە',
                    ),
                filled: true,
                fillColor: _sellFlowManualFieldFill(context),
                labelStyle: _sellFlowManualFieldLabelStyle(context),
                hintStyle: _sellFlowManualFieldHintStyle(context),
                prefixIcon: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFFFF6B00),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
              style: _sellFlowManualFieldTextStyle(context),
              onChanged: (_) => _syncStep3DraftToParent(),
            ),
            SizedBox(height: 24),

            // Quick Sell Option
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _quickSellTextGlobal(context),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          _trLegacyText(
                            context,
                            'Make your listing stand out with a special banner',
                            ar: 'اجعل إعلانك مميزا بشارة خاصة',
                            ku: 'ڕیکلامەکەت بە بانەری تایبەت دیار بکە',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isQuickSell,
                    onChanged: (value) {
                      setState(() {
                        isQuickSell = value;
                      });
                      _syncStep3DraftToParent();
                    },
                    activeThumbColor: Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
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
                        final List<String> missing = [];
                        if (selectedCity == null ||
                            (selectedCity ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.cityLabel);
                        }
                        if (contactPhone == null ||
                            (contactPhone ?? '').trim().isEmpty) {
                          missing.add('Phone');
                        }
                        if (missing.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_pleaseFillRequiredGlobal(context)}: ${missing.join(', ')}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        final parentState = context
                            .findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          _dismissKeyboard();
                          parentState.carData['price'] = selectedPrice;
                          parentState.carData['city'] = selectedCity;
                          parentState.carData['plate_type'] = selectedPlateType;
                          parentState.carData['plate_city'] = selectedPlateCity;
                          parentState.carData['contact_phone'] = contactPhone;
                          parentState.carData['description'] =
                              _descriptionController.text.trim();
                          parentState.carData['is_quick_sell'] = isQuickSell;
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
          ],
        ),
      ),
    ),
    );
  }
}

// Step 4: Photos & Videos
