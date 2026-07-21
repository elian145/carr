part of 'edit_dealer_page.dart';

const Color _editDealerAccent = AppColors.brandOrange;
const int _editDealerMaxPhones = 5;

String normalizeDealerPhoneForVerification(String value) {
  var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('964') && digits.length >= 12) {
    digits = digits.substring(3);
  }
  if (digits.length > 11) {
    digits = digits.substring(digits.length - 11);
  }
  return digits;
}

const List<({String key, String label})> _editDealerDays = [
  (key: 'sun', label: 'Sunday'),
  (key: 'mon', label: 'Monday'),
  (key: 'tue', label: 'Tuesday'),
  (key: 'wed', label: 'Wednesday'),
  (key: 'thu', label: 'Thursday'),
  (key: 'fri', label: 'Friday'),
  (key: 'sat', label: 'Saturday'),
];

class _DayHours {
  bool enabled;
  bool is24h;
  TimeOfDay? open;
  TimeOfDay? close;
  String? legacyText;

  _DayHours({
    required this.enabled,
    required this.is24h,
    this.open,
    this.close,
    this.legacyText,
  });
}

abstract class _EditDealerPageFields extends State<EditDealerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final List<TextEditingController> _phones = [];
  final Set<String> _verifiedPhones = {};
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _coordLat = TextEditingController();
  final _coordLng = TextEditingController();
  final GlobalKey _mapPreviewKey = GlobalKey();
  XFile? _logo;
  XFile? _cover;
  bool _saving = false;
  bool _hydratingProfile = true;
  String? _currentLogo;
  String? _currentCover;
  double? _pickLat;
  double? _pickLng;
  late final Map<String, _DayHours> _openingHours;
  late final Map<String, ExpansibleController> _openingHoursTileControllers;
  late final Map<String, GlobalKey> _openingHoursTileKeys;

  AppLocalizations? get _loc => AppLocalizations.of(context);
}
