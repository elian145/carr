part of 'sell_flow.dart';

mixin _SellStep3Fields on State<SellStep3Page> {
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
}
