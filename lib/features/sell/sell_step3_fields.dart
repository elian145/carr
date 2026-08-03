part of 'sell_flow.dart';

mixin _SellStep3Fields on State<SellStep3Page> {
  static const String _draftKey = 'legacy_sell_draft_step3_v1';
  static const int maxContactPhones = 3;

  final _formKey = GlobalKey<FormState>();
  String? selectedPrice;
  String? selectedCity;
  String? selectedPlateType;
  String? selectedPlateCity;
  /// Primary contact phone (`+964…`), kept for draft/payload compatibility.
  String? contactPhone;
  /// All listing contact phones (`+964…`), max [maxContactPhones].
  List<String> contactPhones = <String>[];
  bool isQuickSell = false;
  String selectedCurrency = 'USD';

  // Focus node for keyboard management
  final FocusNode _priceFocusNode = FocusNode();

  // Controller for price input
  late TextEditingController _priceController;
  final List<TextEditingController> _phoneControllers = <TextEditingController>[];
  final TextEditingController _descriptionController =
      TextEditingController();

  String _localPhoneDigits(String? raw) {
    return (raw ?? '')
        .replaceFirst(RegExp(r'^\+964'), '')
        .replaceAll(RegExp(r'\D'), '');
  }

  /// True when [digits] already appears in another phone row.
  bool _isDuplicateContactPhoneDigits(String digits, int index) {
    final normalized = _localPhoneDigits(digits);
    if (normalized.isEmpty) return false;
    for (var i = 0; i < _phoneControllers.length; i++) {
      if (i == index) continue;
      if (_localPhoneDigits(_phoneControllers[i].text) == normalized) {
        return true;
      }
    }
    return false;
  }

  /// True when another phone row (not [index]) has digits entered.
  bool _hasContactPhoneDigitsBesides(int index) {
    for (var i = 0; i < _phoneControllers.length; i++) {
      if (i == index) continue;
      if (_phoneControllers[i].text.trim().isNotEmpty) return true;
    }
    return false;
  }

  List<String> _collectContactPhonesFromControllers() {
    final out = <String>[];
    final seen = <String>{};
    for (final c in _phoneControllers) {
      final digits = c.text.trim();
      if (digits.isEmpty) continue;
      final full = '+964$digits';
      final key = digits;
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(full);
      if (out.length >= maxContactPhones) break;
    }
    return out;
  }

  void _applyContactPhonesToControllers(List<String> phones) {
    final normalized = phones
        .map(_localPhoneDigits)
        .where((d) => d.isNotEmpty)
        .take(maxContactPhones)
        .toList();
    while (_phoneControllers.length > normalized.length &&
        _phoneControllers.length > 1) {
      _phoneControllers.removeLast().dispose();
    }
    if (_phoneControllers.isEmpty) {
      _phoneControllers.add(TextEditingController());
    }
    while (_phoneControllers.length < normalized.length) {
      _phoneControllers.add(TextEditingController());
    }
    for (var i = 0; i < _phoneControllers.length; i++) {
      _phoneControllers[i].text =
          i < normalized.length ? normalized[i] : '';
    }
  }

  // Currency conversion method
}
