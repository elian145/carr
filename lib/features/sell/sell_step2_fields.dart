part of 'sell_flow.dart';

abstract class _SellStep2Fields extends State<SellStep2Page> {
  final _formKey = GlobalKey<FormState>();
  static const String _draftKey = 'legacy_sell_draft_step2_v1';
  String? selectedMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedDriveType;

  /// Lowercase code sent as `region_specs` (see [kCarRegionSpecCodes]).
  String? selectedRegionSpecs;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCylinderCount;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? selectedVin;
  bool errMileage = false;
  bool errCondition = false;
  bool errTransmission = false;
  bool errFuelType = false;
  bool errBodyType = false;
  bool errColor = false;
  bool errDrive = false;
  bool errRegionSpecs = false;
  bool errSeating = false;
  bool errEngineSize = false;
  bool errCylinderCount = false;
  bool errTitle = false;
  bool errDamagedParts = false;
  bool isMileageManualInput = false;
  bool isEngineSizeManualInput = false;

  /// Bumps when step 1 applies catalog/online specs so we re-hydrate when returning to step 2.
  int? _lastSpecsHydrateStamp;

  CarSpecIndex? _specIdx;
  CatalogSellFieldOptions? _catalogSellOpts;

  // Focus nodes for keyboard management
  final FocusNode _mileageFocusNode = FocusNode();
  final FocusNode _engineSizeFocusNode = FocusNode();

  // Controllers for manual inputs
  late TextEditingController _mileageController;
  late TextEditingController _engineSizeController;
  late TextEditingController _vinController;

}
