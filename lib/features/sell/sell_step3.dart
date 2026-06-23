part of 'sell_flow.dart';
class SellStep3Page extends StatefulWidget {
  const SellStep3Page({super.key});

  @override
  State<SellStep3Page> createState() => _SellStep3PageState();
}

mixin _SellStep3Body on State<SellStep3Page> {
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

}

class _SellStep3PageState extends State<SellStep3Page>
    with _SellStep3Body, _SellStep3Build {}
