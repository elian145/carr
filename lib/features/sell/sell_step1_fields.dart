part of 'sell_flow.dart';

abstract class _SellStep1Fields extends State<SellStep1Page> {
  final _formKey = GlobalKey<FormState>();
  static const String _draftKey = 'legacy_sell_draft_step1_v1';
  String? selectedBrand;
  String? selectedModel;
  String? selectedTrim;
  String? selectedYear;
  bool errBrand = false;
  bool errModel = false;
  bool errTrim = false;
  bool errYear = false;
  bool isYearManualInput = false;

  CarSpecIndex? _specIdx;
  String? _specLoadErr;
  bool _specDbReady = false;
  int? _dsModelId;
  int? _catYear;

  // Focus node for keyboard management
  final FocusNode _yearFocusNode = FocusNode();

  // Controller for year input
  late TextEditingController _yearController;

}
