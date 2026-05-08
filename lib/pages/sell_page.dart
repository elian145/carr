import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../data/car_catalog.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/car_spec_index.dart';
import '../models/online_spec_variant.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/prefs/sell_listing_draft_prefs.dart';

class SellPage extends StatefulWidget {
  const SellPage({super.key});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  final _formKey = GlobalKey<FormState>();

  final _year = TextEditingController();
  final _mileage = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();

  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedTrim;

  CarSpecIndex? _specIndex;
  String? _specLoadError;
  /// True after [CarSpecIndex.loadWithResult] finishes (success or failure).
  bool _specDbLoadDone = false;
  int? _datasetModelId;
  int? _catalogYear;
  /// Bumps so dropdowns rebuild after catalog apply (Material dropdown cache).
  int _specDropdownKey = 0;

  final _engineSizeCtl = TextEditingController();
  final _cylinderCtl = TextEditingController();
  final _fuelEconomyCtl = TextEditingController();
  final _seatingCtl = TextEditingController();

  String _engineType = 'gasoline';
  String _fuelType = 'gasoline';
  String _transmission = 'automatic';
  String _driveType = 'fwd';
  String _condition = 'used';
  String _bodyType = 'sedan';
  String _currency = 'USD';

  final List<XFile> _images = <XFile>[];
  final List<XFile> _videos = <XFile>[];
  bool _submitting = false;
  String? _error;
  String? _stage;
  Timer? _draftSaveTimer;
  bool _restoringDraft = false;
  bool _draftLoaded = false;
  bool _draftExists = false;
  bool _draftIsComplete = false;
  Map<String, dynamic>? _draftPreviewData;
  String? _draftOwnerKey;

  /// When the bundled catalog provides 2+ distinct values, the matching field becomes a dropdown
  /// limited to these options (cleared when applying catalog specs).
  /// Display strings, e.g. `3.0`, `3.0 D`, `2.4 T` (from catalog variants).
  List<String>? _engineSizeDisplayOptions;
  List<int>? _cylinderOptions;
  List<String>? _fuelEconomyOptions;
  List<int>? _seatingOptions;
  List<String>? _transmissionOptions;
  List<String>? _drivetrainOptions;
  List<String>? _bodyTypeOptions;
  List<String>? _engineTypeOptions;
  List<String>? _fuelTypeOptions;

  /// Populated after catalog apply: paired engine size, cylinders, transmission, etc. per row.
  List<OnlineSpecVariant>? _onlineSpecVariants;

  @override
  void initState() {
    super.initState();
    _draftOwnerKey = _buildDraftOwnerKey();
    _year.addListener(_onListingYearChanged);
    _mileage.addListener(_onDraftFieldChanged);
    _price.addListener(_onDraftFieldChanged);
    _location.addListener(_onDraftFieldChanged);
    _description.addListener(_onDraftFieldChanged);
    _engineSizeCtl.addListener(_onDraftFieldChanged);
    _cylinderCtl.addListener(_onDraftFieldChanged);
    _fuelEconomyCtl.addListener(_onDraftFieldChanged);
    _seatingCtl.addListener(_onDraftFieldChanged);
    unawaited(_loadDraftPreview());
    CarSpecIndex.loadWithResult().then((r) {
      if (!mounted) return;
      setState(() {
        _specIndex = r.index;
        _specLoadError = r.errorMessage;
        _specDbLoadDone = true;
      });
      _scheduleRefreshDataset();
    });
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    unawaited(_saveDraft(immediate: true));
    _year.removeListener(_onListingYearChanged);
    _mileage.removeListener(_onDraftFieldChanged);
    _price.removeListener(_onDraftFieldChanged);
    _location.removeListener(_onDraftFieldChanged);
    _description.removeListener(_onDraftFieldChanged);
    _engineSizeCtl.removeListener(_onDraftFieldChanged);
    _cylinderCtl.removeListener(_onDraftFieldChanged);
    _fuelEconomyCtl.removeListener(_onDraftFieldChanged);
    _seatingCtl.removeListener(_onDraftFieldChanged);
    _year.dispose();
    _mileage.dispose();
    _price.dispose();
    _location.dispose();
    _description.dispose();
    _engineSizeCtl.dispose();
    _cylinderCtl.dispose();
    _fuelEconomyCtl.dispose();
    _seatingCtl.dispose();
    super.dispose();
  }

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
    final raw = (user?['public_id'] ??
            user?['id'] ??
            user?['username'] ??
            user?['email'] ??
            'guest')
        .toString()
        .trim();
    return raw.isEmpty ? 'guest' : raw;
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
        (data['image_paths'] is List && (data['image_paths'] as List).isNotEmpty) ||
        (data['video_paths'] is List && (data['video_paths'] as List).isNotEmpty) ||
        (data['engine_type'] ?? 'gasoline') != 'gasoline' ||
        (data['fuel_type'] ?? 'gasoline') != 'gasoline' ||
        (data['transmission'] ?? 'automatic') != 'automatic' ||
        (data['drive_type'] ?? 'fwd') != 'fwd' ||
        (data['condition'] ?? 'used') != 'used' ||
        (data['body_type'] ?? 'sedan') != 'sedan' ||
        (data['currency'] ?? 'USD') != 'USD';
  }

  Future<void> _loadDraftPreview() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final draft = await SellListingDraftPrefs.load(owner);
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
    return _images.isNotEmpty || _videos.isNotEmpty;
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
      await SellListingDraftPrefs.clear(owner);
      if (mounted) {
        setState(() {
          _draftExists = false;
          _draftIsComplete = false;
          _draftLoaded = true;
        });
      }
      return;
    }

    final draft = _buildDraftData();
    await SellListingDraftPrefs.save(owner, draft);
    if (!mounted) return;
    setState(() {
      _draftExists = true;
      _draftIsComplete = draft['complete'] == true;
      _draftLoaded = true;
      _draftPreviewData = draft;
    });
  }

  Future<void> _restoreDraft() async {
    final owner = _draftOwnerKey ??= _buildDraftOwnerKey();
    final draft = await SellListingDraftPrefs.load(owner);
    if (!mounted) return;
    if (draft == null) {
      setState(() {
        _draftLoaded = true;
        _draftExists = false;
        _draftIsComplete = false;
      });
      return;
    }

    _restoringDraft = true;
    try {
      final imagePaths = (draft['image_paths'] is List)
          ? (draft['image_paths'] as List)
              .map((e) => e.toString())
              .where((path) => path.trim().isNotEmpty && File(path).existsSync())
              .toList()
          : <String>[];
      final videoPaths = (draft['video_paths'] is List)
          ? (draft['video_paths'] as List)
              .map((e) => e.toString())
              .where((path) => path.trim().isNotEmpty && File(path).existsSync())
              .toList()
          : <String>[];

      final loadedDraft = <String, dynamic>{
        'brand': (draft['brand'] ?? '').toString().trim(),
        'model': (draft['model'] ?? '').toString().trim(),
        'trim': (draft['trim'] ?? '').toString().trim(),
        'year': (draft['year'] ?? '').toString().trim(),
        'mileage': (draft['mileage'] ?? '').toString().trim(),
        'price': (draft['price'] ?? '').toString().trim(),
        'currency': (draft['currency'] ?? 'USD').toString(),
        'location': (draft['location'] ?? '').toString().trim(),
        'description': (draft['description'] ?? '').toString().trim(),
        'engine_type': (draft['engine_type'] ?? 'gasoline').toString(),
        'fuel_type': (draft['fuel_type'] ?? 'gasoline').toString(),
        'transmission': (draft['transmission'] ?? 'automatic').toString(),
        'drive_type': (draft['drive_type'] ?? 'fwd').toString(),
        'condition': (draft['condition'] ?? 'used').toString(),
        'body_type': (draft['body_type'] ?? 'sedan').toString(),
        'engine_size': (draft['engine_size'] ?? '').toString().trim(),
        'cylinder_count': (draft['cylinder_count'] ?? '').toString().trim(),
        'fuel_economy': (draft['fuel_economy'] ?? '').toString().trim(),
        'seating': (draft['seating'] ?? '').toString().trim(),
        'image_paths': imagePaths,
        'video_paths': videoPaths,
      };
      final hasMeaningfulContent = loadedDraft.entries.any((entry) {
        final value = entry.value;
        if (value is String) return value.trim().isNotEmpty;
        if (value is List) return value.isNotEmpty;
        return value != null;
      }) && (loadedDraft['brand'].toString().isNotEmpty ||
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
          loadedDraft['currency'] != 'USD');
      if (!hasMeaningfulContent) {
        await SellListingDraftPrefs.clear(owner);
        if (!mounted) return;
        setState(() {
          _draftLoaded = true;
          _draftExists = false;
          _draftIsComplete = false;
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
        _catalogYear = int.tryParse((draft['catalog_year'] ?? '').toString());
        _datasetModelId = int.tryParse((draft['dataset_model_id'] ?? '').toString());
        _images
          ..clear()
          ..addAll(imagePaths.map((path) => XFile(path)));
        _videos
          ..clear()
          ..addAll(videoPaths.map((path) => XFile(path)));
        _draftExists = true;
        _draftIsComplete = draft['complete'] == true || _isListingComplete();
        _draftLoaded = true;
        _draftPreviewData = draft;
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
      await SellListingDraftPrefs.clear(owner);
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
        _images.clear();
        _videos.clear();
        _clearOnlineSpecOptionLists();
        _draftExists = false;
        _draftIsComplete = false;
        _draftLoaded = true;
      });
    } finally {
      _restoringDraft = false;
      _scheduleRefreshDataset();
    }
  }

  void _refreshDatasetPicker() {
    final idx = _specIndex;
    final brand = _selectedBrand;
    final model = _selectedModel;

    int? newModelId = _datasetModelId;
    int? newYear = _catalogYear;

    if (idx == null ||
        brand == null ||
        model == null ||
        !idx.hasCoverage(brand, model)) {
      newModelId = null;
      newYear = null;
    } else {
      final bid = idx.datasetBrandId(brand);
      if (bid == null) {
        newModelId = null;
        newYear = null;
      } else {
        final variants = idx.variantsForAppModel(brand, model);
        if (variants.isEmpty) {
          newModelId = null;
          newYear = null;
        } else {
          final formYear = int.tryParse(_year.text.trim());
          final years = idx.yearsForCatalogStep(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
          );
          if (years.isEmpty) {
            newModelId = null;
            newYear = null;
          } else {
            int resolvedYear;
            if (formYear != null && years.contains(formYear)) {
              resolvedYear = formYear;
            } else if (newYear != null && years.contains(newYear)) {
              resolvedYear = newYear;
            } else {
              resolvedYear = years.first;
            }
            newYear = resolvedYear;
            final preferred = idx.suggestDatasetModelIdForFormYear(
              brand,
              model,
              CarSpecIndex.catalogAutofillModelOnly,
              resolvedYear,
            );
            var modelId = newModelId ?? 0;
            if (modelId == 0 || !variants.any((v) => v.id == modelId)) {
              modelId = preferred ?? variants.first.id;
            } else if (!idx.datasetVariantCoversYear(modelId, resolvedYear)) {
              modelId = preferred ?? modelId;
            }
            newModelId = modelId;
          }
        }
      }
    }

    setState(() {
      _datasetModelId = newModelId;
      _catalogYear = newYear;
    });
  }

  /// Fills constrained step-2 lists from bundled-catalog [OnlineSpecVariant] rows.
  void _applyConstrainedOptionsFromCatalogVariants(List<OnlineSpecVariant> vs) {
    if (vs.isEmpty) return;
    final tr = <String>{};
    final dr = <String>{};
    final body = <String>{};
    final engt = <String>{};
    final fuel = <String>{};
    final sizeLabels = <String>[];
    final seenSizes = <String>{};
    final cyl = <int>{};
    final seat = <int>{};
    final fe = <String>{};
    for (final v in vs) {
      if (v.transmission != null) tr.add(v.transmission!);
      if (v.drivetrain != null) dr.add(v.drivetrain!);
      if (v.bodyType != null) body.add(v.bodyType!);
      if (v.engineType != null) engt.add(v.engineType!);
      if (v.fuelType != null) fuel.add(v.fuelType!);
      if (v.engineSizeLiters != null && v.engineSizeLiters! > 0.001) {
        final lit = double.parse(v.engineSizeLiters!.toStringAsFixed(1));
        final label = '${lit.toStringAsFixed(1)}${v.displacementSuffix}';
        if (seenSizes.add(label)) sizeLabels.add(label);
      }
      if (v.cylinderCount != null && v.cylinderCount! > 0) {
        cyl.add(v.cylinderCount!);
      }
      if (v.seating != null && v.seating! > 0) seat.add(v.seating!);
      if (v.fuelEconomy != null && v.fuelEconomy!.trim().isNotEmpty) {
        fe.add(v.fuelEconomy!.trim());
      }
    }
    _transmissionOptions = tr.isNotEmpty ? (tr.toList()..sort()) : null;
    _drivetrainOptions = dr.isNotEmpty ? (dr.toList()..sort()) : null;
    _bodyTypeOptions = body.isNotEmpty ? (body.toList()..sort()) : null;
    _engineTypeOptions = engt.isNotEmpty ? (engt.toList()..sort()) : null;
    _fuelTypeOptions = fuel.isNotEmpty ? (fuel.toList()..sort()) : null;
    if (sizeLabels.isNotEmpty) {
      sizeLabels.sort((a, b) {
        final la = OnlineSpecVariant.parseLeadingEngineLiters(a) ?? 0;
        final lb = OnlineSpecVariant.parseLeadingEngineLiters(b) ?? 0;
        final c = la.compareTo(lb);
        if (c != 0) return c;
        return a.compareTo(b);
      });
      _engineSizeDisplayOptions = sizeLabels;
    } else {
      _engineSizeDisplayOptions = null;
    }
    _cylinderOptions = cyl.isNotEmpty ? (cyl.toList()..sort()) : null;
    _seatingOptions = seat.isNotEmpty ? (seat.toList()..sort()) : null;
    _fuelEconomyOptions = fe.isNotEmpty ? (fe.toList()..sort()) : null;
  }

  void _applyCatalogSpecs() {
    final idx = _specIndex;
    if (idx == null || _catalogYear == null) {
      return;
    }
    final brand = (_selectedBrand ?? '').trim();
    final model = (_selectedModel ?? '').trim();
    if (brand.isEmpty || model.isEmpty) return;

    final rep = idx.representativeForCatalogSell(
      brand,
      model,
      CarSpecIndex.catalogAutofillModelOnly,
      _catalogYear!,
    );
    CatalogSpecFields? fields = rep?.fields;
    if (fields == null) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.invalidField ??
                'No specs for this year — pick another year or variant.',
          ),
        ),
      );
      return;
    }
    final specFields = fields;

    var catVs = (brand.isNotEmpty && model.isNotEmpty)
        ? idx.catalogSellSpecVariants(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            _catalogYear!,
          )
        : <OnlineSpecVariant>[];
    if (catVs.isEmpty) {
      catVs = [
        OnlineSpecVariant(
          engineSizeLiters: specFields.engineSizeLiters,
          displacementSuffix: specFields.displacementSuffix,
          cylinderCount: specFields.cylinderCount,
          seating: specFields.seating,
          fuelEconomy: specFields.fuelEconomy,
          transmission: specFields.transmission,
          drivetrain: specFields.driveType,
          bodyType: specFields.bodyType,
          engineType: specFields.engineType,
          fuelType: specFields.fuelType,
        ),
      ];
    }

    setState(() {
      if (rep != null) {
        _datasetModelId = rep.datasetModelId;
      }
      _onlineSpecVariants = List<OnlineSpecVariant>.from(catVs);
      _applyConstrainedOptionsFromCatalogVariants(catVs);
      _engineType = specFields.engineType;
      _fuelType = specFields.fuelType;
      _transmission = specFields.transmission;
      _driveType = specFields.driveType;
      _bodyType = specFields.bodyType;
      _specDropdownKey++;
      _engineSizeCtl.text = specFields.engineSizeLiters != null
          ? '${specFields.engineSizeLiters!.toStringAsFixed(1)}${specFields.displacementSuffix}'
          : '';
      _cylinderCtl.text =
          specFields.cylinderCount != null ? '${specFields.cylinderCount}' : '';
      _fuelEconomyCtl.text = specFields.fuelEconomy ?? '';
      _seatingCtl.text = specFields.seating != null ? '${specFields.seating}' : '';
      _year.text = '${_catalogYear!}';
      _syncConstrainedSelectionsAfterCatalogApply();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Applied specs from catalog')),
    );
    _scheduleDraftSave();
  }

  void _scheduleRefreshDataset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDatasetPicker();
    });
  }

  void _onListingYearChanged() {
    _scheduleRefreshDataset();
    _scheduleDraftSave();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _images.addAll(picked);
      });
      _scheduleDraftSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _videos.add(picked);
      });
      _scheduleDraftSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
      });
    }
  }

  Future<void> _uploadCarImages(String carId) async {
    try {
      final publicUrls = <String>[];
      for (final file in _images) {
        final sign = await ApiService.signR2ImageUpload(
          filename: file.name,
          contentType: file.mimeType,
        );
        final uploadUrl = sign['upload_url'] as String?;
        final publicUrl = sign['public_url'] as String?;
        if (uploadUrl == null ||
            uploadUrl.isEmpty ||
            publicUrl == null ||
            publicUrl.isEmpty) {
          await ApiService.uploadCarImages(carId, _images);
          return;
        }
        await ApiService.uploadToSignedUpload(uploadUrl, file);
        publicUrls.add(publicUrl);
      }
      await ApiService.attachCarImageUrls(carId, publicUrls);
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        await ApiService.uploadCarImages(carId, _images);
      } else {
        rethrow;
      }
    } catch (_) {
      await ApiService.uploadCarImages(carId, _images);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _stage = null;
    });

    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.loginRequired ?? 'Login required')),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.pleaseFixHighlightedFields ?? 'Please fix the highlighted fields',
          ),
        ),
      );
      return;
    }

    final int year = int.tryParse(_year.text.trim()) ?? 0;
    final int mileage = int.tryParse(_mileage.text.trim()) ?? 0;
    final double price = double.tryParse(_price.text.trim()) ?? 0;

    setState(() {
      _submitting = true;
      _stage = loc?.creatingListing ?? 'Creating listing...';
    });
    try {
      final body = <String, dynamic>{
        'brand': _selectedBrand!.trim(),
        'model': _selectedModel!.trim(),
        'trim': _selectedTrim!.trim(),
        'year': year,
        'mileage': mileage,
        'engine_type': _engineType,
        'fuel_type': _fuelType,
        'transmission': _transmission,
        'drive_type': _driveType,
        'condition': _condition,
        'body_type': _bodyType,
        'price': price,
        'currency': _currency,
        'location': _location.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      };
      final eng = OnlineSpecVariant.parseLeadingEngineLiters(
        _engineSizeCtl.text.trim(),
      );
      if (eng != null && eng > 0) body['engine_size'] = eng;
      final cyl = int.tryParse(_cylinderCtl.text.trim());
      if (cyl != null && cyl > 0) body['cylinder_count'] = cyl;
      final fe = _fuelEconomyCtl.text.trim();
      if (fe.isNotEmpty) body['fuel_economy'] = fe;
      final seat = int.tryParse(_seatingCtl.text.trim());
      if (seat != null && seat > 0) body['seating'] = seat;

      final created = await ApiService.createCar(body);

      final car = (created['car'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(created['car'])
          : <String, dynamic>{};
      final carId = (car['id'] ?? car['public_id'] ?? '').toString().trim();
      if (carId.isEmpty) {
        throw StateError('Car created but missing id');
      }

      if (_images.isNotEmpty) {
        setState(() => _stage = loc?.uploadingPhotos ?? 'Uploading photos...');
        await _uploadCarImages(carId);
      }
      if (_videos.isNotEmpty) {
        setState(() => _stage = loc?.uploadingVideos ?? 'Uploading videos...');
        await ApiService.uploadCarVideos(carId, _videos);
      }

      if (!mounted) return;
      await SellListingDraftPrefs.clear(_draftOwnerKey ?? _buildDraftOwnerKey());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc?.listingCreated ?? 'Listing created')),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/car_detail',
        arguments: {'carId': carId},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.couldNotSubmitListing ??
              'Could not submit listing. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _stage = null;
        });
      }
    }
  }

  /// Shown under trim: loading DB, error, "no match" explanation, or catalog card.
  Widget _trimDependentCatalogSection(AppLocalizations? loc) {
    final trim = (_selectedTrim ?? '').trim();
    if (trim.isEmpty) return const SizedBox.shrink();

    final brand = _selectedBrand;
    final model = _selectedModel;
    if (brand == null || model == null) return const SizedBox.shrink();

    if (!_specDbLoadDone) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Loading vehicle spec database…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_specIndex == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spec database not available',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _specLoadError ??
                    'The JSON asset did not load. Run flutter clean, flutter pub get, then stop and restart the app (not hot reload).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (!_specIndex!.hasCoverage(brand, model)) {
      final hints = _specIndex!.catalogCoverageHints();
      final sample = hints.take(12).join(' · ');
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No catalog auto-fill for this pick',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'You selected $brand $model. The bundled database only covers certain model lines (examples below). Pick one of those to unlock catalog year and “Apply to form”.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sample.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  sample,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if (hints.length > 12)
                Text(
                  '… and ${hints.length - 12} more variant rows in the file.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      );
    }

    return _catalogSpecDetailsCard(loc);
  }

  Widget _catalogSpecDetailsCard(AppLocalizations? loc) {
    final idx = _specIndex;
    final brand = _selectedBrand;
    final model = _selectedModel;
    if (idx == null || brand == null || model == null) {
      return const SizedBox.shrink();
    }
    final variants = idx.variantsForAppModel(brand, model);
    if (variants.isEmpty) return const SizedBox.shrink();

    final listingYear = int.tryParse(_year.text.trim());
    final years = idx.yearsForCatalogStep(
      brand,
      model,
      CarSpecIndex.catalogAutofillModelOnly,
    );
    if (years.isEmpty) return const SizedBox.shrink();

    final CatalogSpecFields? preview = _catalogYear != null
        ? idx
            .representativeForCatalogSell(
              brand,
              model,
              CarSpecIndex.catalogAutofillModelOnly,
              _catalogYear!,
            )
            ?.fields
        : null;
    final unionPreview = _catalogYear != null
        ? idx.sellFieldOptionsUnion(
            brand,
            model,
            CarSpecIndex.catalogAutofillModelOnly,
            _catalogYear!,
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Catalog match',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              listingYear != null
                  ? 'Pick catalog year and apply. Step 2 lists every engine and spec row we have for this model line—choose what matches your car.'
                  : 'Enter a year above, pick catalog year, then apply. Choose engine and other specs in step 2.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (preview != null || unionPreview != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.28),
                  ),
                ),
                child: Text(
                  () {
                    var engExtra = '';
                    if (unionPreview != null &&
                        unionPreview.engineSizes.length > 1) {
                      final engList = unionPreview.engineSizes.toList()
                        ..sort((a, b) {
                          final la =
                              OnlineSpecVariant.parseLeadingEngineLiters(a) ??
                                  0;
                          final lb =
                              OnlineSpecVariant.parseLeadingEngineLiters(b) ??
                                  0;
                          final c = la.compareTo(lb);
                          if (c != 0) return c;
                          return a.compareTo(b);
                        });
                      engExtra = '\nStep 2 engines: ${engList.join(', ')}';
                    }
                    if (preview != null) {
                      return 'Will set (smallest engine in list — pick another in step 2 if needed): ${preview.engineType}, ${preview.transmission}, ${preview.driveType.toUpperCase()}, ${preview.bodyType}'
                          '${preview.engineSizeLiters != null ? ', ${preview.engineSizeLiters!.toStringAsFixed(1)}${preview.displacementSuffix} L engine' : ''}'
                          '${preview.cylinderCount != null ? ', ${preview.cylinderCount} cyl' : ''}$engExtra';
                    }
                    return 'Catalog has options for this year — apply to load step 2 (engine, cylinders, etc.).$engExtra';
                  }(),
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ] else if (_catalogYear != null && years.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'No spec row for this year — try another year or variant.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (years.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _catalogYear != null && years.contains(_catalogYear)
                    ? _catalogYear
                    : years.first,
                decoration: InputDecoration(
                  labelText: loc?.yearLabel ?? 'Model year (catalog)',
                ),
                items: years
                    .map(
                      (y) => DropdownMenuItem(
                        value: y,
                        child: Text('$y'),
                      ),
                    )
                    .toList(),
                onChanged: (y) {
                  if (y == null) return;
                  setState(() => _catalogYear = y);
                  _scheduleRefreshDataset();
                  _scheduleDraftSave();
                },
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_catalogYear != null &&
                      (preview != null || unionPreview != null) &&
                      !_submitting)
                  ? _applyCatalogSpecs
                  : null,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Apply to form below'),
            ),
          ],
        ),
      ),
    );
  }

  static const Map<String, String> _kEngineTypeLabels = {
    'gasoline': 'Gasoline',
    'diesel': 'Diesel',
    'hybrid': 'Hybrid',
    'electric': 'Electric',
  };

  static const Map<String, String> _kDriveLabels = {
    'fwd': 'FWD',
    'rwd': 'RWD',
    'awd': 'AWD',
    '4wd': '4WD',
  };

  static const Map<String, String> _kBodyLabels = {
    'sedan': 'Sedan',
    'suv': 'SUV',
    'hatchback': 'Hatchback',
    'coupe': 'Coupe',
    'pickup': 'Pickup',
    'van': 'Van',
    'convertible': 'Convertible',
    'wagon': 'Wagon',
  };

  String _coerceInList(String value, List<String> allowed) {
    if (allowed.contains(value)) return value;
    return allowed.first;
  }

  double? _parsedEngineLiters() {
    final v = OnlineSpecVariant.parseLeadingEngineLiters(_engineSizeCtl.text);
    if (v == null) return null;
    return double.parse(v.toStringAsFixed(1));
  }

  String _coerceEngineDisplayPick(List<String> opts) {
    final t = _engineSizeCtl.text.trim();
    if (t.isNotEmpty && opts.contains(t)) return t;
    final p = OnlineSpecVariant.parseLeadingEngineLiters(t);
    if (p != null) {
      for (final o in opts) {
        final oL = OnlineSpecVariant.parseLeadingEngineLiters(o);
        if (oL != null && (oL - p).abs() < 0.06) return o;
      }
    }
    return opts.first;
  }

  List<String>? _engineFuelConstrainedOptions() {
    final eng = _engineTypeOptions;
    final fuel = _fuelTypeOptions;
    if ((eng == null || eng.isEmpty) && (fuel == null || fuel.isEmpty)) {
      return null;
    }
    if (eng != null &&
        eng.isNotEmpty &&
        fuel != null &&
        fuel.isNotEmpty) {
      final out = <String>[];
      final seen = <String>{};
      for (final x in [...eng, ...fuel]) {
        if (seen.add(x)) out.add(x);
      }
      return out;
    }
    if (eng != null && eng.isNotEmpty) return List<String>.from(eng);
    if (fuel != null && fuel.isNotEmpty) return List<String>.from(fuel);
    return null;
  }

  String? _labeledMultiHint(List<String> keys, Map<String, String> labels) {
    if (keys.length < 2) return null;
    return keys.map((k) => labels[k] ?? k).join(' · ');
  }

  void _applyOnlineVariantToForm(OnlineSpecVariant v) {
    if (v.engineSizeLiters != null) {
      _engineSizeCtl.text =
          '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
    }
    if (v.cylinderCount != null) {
      _cylinderCtl.text = '${v.cylinderCount}';
    }
    if (v.fuelEconomy != null) {
      _fuelEconomyCtl.text = v.fuelEconomy!;
    }
    if (v.seating != null) {
      _seatingCtl.text = '${v.seating}';
    }
    if (v.transmission != null) _transmission = v.transmission!;
    if (v.drivetrain != null) _driveType = v.drivetrain!;
    if (v.bodyType != null) _bodyType = v.bodyType!;
    if (v.engineType != null) _engineType = v.engineType!;
    if (v.fuelType != null) _fuelType = v.fuelType!;
  }

  /// After user changes one spec, align other fields to the matching catalog variant (if any).
  void _syncCorrelatedFromOnlineVariants(
    Set<String> anchors, {
    double? engineLiters,
    int? cylinders,
    String? transmission,
    String? drivetrain,
    String? bodyType,
    String? engineType,
    String? fuelType,
    String? fuelEconomy,
    int? seating,
  }) {
    final vs = _onlineSpecVariants;
    if (vs == null || vs.isEmpty) return;
    final fe = fuelEconomy ?? () {
      final t = _fuelEconomyCtl.text.trim();
      return t.isEmpty ? null : t;
    }();
    final m = OnlineSpecVariant.matchBestAnchored(
      vs,
      anchors,
      engineLiters: engineLiters ?? _parsedEngineLiters(),
      cylinders: cylinders ?? int.tryParse(_cylinderCtl.text.trim()),
      transmission: transmission ?? _transmission,
      drivetrain: drivetrain ?? _driveType,
      bodyType: bodyType ?? _bodyType,
      engineType: engineType ?? _engineType,
      fuelType: fuelType ?? _fuelType,
      fuelEconomy: fe,
      seating: seating ?? int.tryParse(_seatingCtl.text.trim()),
      currentTransmission: _transmission,
      currentDrivetrain: _driveType,
      currentSeating: int.tryParse(_seatingCtl.text.trim()),
    );
    if (m != null) {
      _applyOnlineVariantToForm(m);
      _specDropdownKey++;
    }
  }

  /// Keeps controllers / enum strings inside catalog option sets so submit matches the UI.
  void _syncConstrainedSelectionsAfterCatalogApply() {
    if (_transmissionOptions != null && _transmissionOptions!.isNotEmpty) {
      _transmission = _coerceInList(_transmission, _transmissionOptions!);
    }
    if (_drivetrainOptions != null && _drivetrainOptions!.isNotEmpty) {
      _driveType = _coerceInList(_driveType, _drivetrainOptions!);
    }
    if (_bodyTypeOptions != null && _bodyTypeOptions!.isNotEmpty) {
      _bodyType = _coerceInList(_bodyType, _bodyTypeOptions!);
    }
    final engOpts = _engineFuelConstrainedOptions();
    if (engOpts != null) {
      _engineType = _coerceInList(_engineType, engOpts);
      _fuelType = _coerceInList(_fuelType, engOpts);
    }
    if (_engineSizeDisplayOptions != null &&
        _engineSizeDisplayOptions!.isNotEmpty) {
      final opts = _engineSizeDisplayOptions!;
      final t = _engineSizeCtl.text.trim();
      final exact = t.isNotEmpty && opts.contains(t);
      final p = OnlineSpecVariant.parseLeadingEngineLiters(t);
      final fuzzy = p != null &&
          opts.any((o) {
            final oL = OnlineSpecVariant.parseLeadingEngineLiters(o);
            return oL != null && (oL - p).abs() < 0.06;
          });
      if (!exact && !fuzzy) {
        _engineSizeCtl.text = opts.first;
      }
    }
    if (_cylinderOptions != null && _cylinderOptions!.isNotEmpty) {
      final c = int.tryParse(_cylinderCtl.text.trim());
      if (c == null || !_cylinderOptions!.contains(c)) {
        _cylinderCtl.text = '${_cylinderOptions!.first}';
      }
    }
    if (_seatingOptions != null && _seatingOptions!.isNotEmpty) {
      final c = int.tryParse(_seatingCtl.text.trim());
      if (c == null || !_seatingOptions!.contains(c)) {
        _seatingCtl.text = '${_seatingOptions!.first}';
      }
    }
    if (_fuelEconomyOptions != null && _fuelEconomyOptions!.isNotEmpty) {
      final t = _fuelEconomyCtl.text.trim();
      if (!_fuelEconomyOptions!.contains(t)) {
        _fuelEconomyCtl.text = _fuelEconomyOptions!.first;
      }
    }
  }

  Widget _engineTypeField(AppLocalizations? loc) {
    final constrained = _engineFuelConstrainedOptions();
    final value = constrained != null
        ? _coerceInList(_engineType, constrained)
        : _engineType;
    final items = constrained != null
        ? constrained
            .map(
              (k) => DropdownMenuItem<String>(
                value: k,
                child: Text(_kEngineTypeLabels[k] ?? k),
              ),
            )
            .toList()
        : const [
            DropdownMenuItem(value: 'gasoline', child: Text('Gasoline')),
            DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
            DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
            DropdownMenuItem(value: 'electric', child: Text('Electric')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('eng_$_specDropdownKey$value${constrained?.join() ?? 'full'}'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.engineTypeLabel ?? 'Engine type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kEngineTypeLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          final nv = v ?? _engineType;
          _engineType = nv;
          _fuelType = nv;
          _syncCorrelatedFromOnlineVariants(
            {'engt', 'fuel'},
            engineType: nv,
            fuelType: nv,
          );
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _transmissionField(AppLocalizations? loc) {
    final constrained =
        _transmissionOptions != null && _transmissionOptions!.isNotEmpty
            ? _transmissionOptions!
            : null;
    final value = constrained != null
        ? _coerceInList(_transmission, constrained)
        : _transmission;
    final items = constrained != null
        ? constrained
            .map(
              (k) => DropdownMenuItem<String>(
                value: k,
                child: Text(k == 'automatic' ? 'Automatic' : 'Manual'),
              ),
            )
            .toList()
        : const [
            DropdownMenuItem(value: 'automatic', child: Text('Automatic')),
            DropdownMenuItem(value: 'manual', child: Text('Manual')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('tr_$_specDropdownKey$value${constrained?.join() ?? 'full'}'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.transmissionLabel ?? 'Transmission',
        helperText: constrained != null && constrained.length >= 2
            ? constrained
                .map((k) => k == 'automatic' ? 'Automatic' : 'Manual')
                .join(' · ')
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _transmission = v ?? _transmission;
          _syncCorrelatedFromOnlineVariants(
            {'tr'},
            transmission: _transmission,
          );
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _driveTypeField(AppLocalizations? loc) {
    final constrained =
        _drivetrainOptions != null && _drivetrainOptions!.isNotEmpty
            ? _drivetrainOptions!
            : null;
    final value =
        constrained != null ? _coerceInList(_driveType, constrained) : _driveType;
    final items = constrained != null
        ? constrained
            .map(
              (k) => DropdownMenuItem<String>(
                value: k,
                child: Text(_kDriveLabels[k] ?? k.toUpperCase()),
              ),
            )
            .toList()
        : const [
            DropdownMenuItem(value: 'fwd', child: Text('FWD')),
            DropdownMenuItem(value: 'rwd', child: Text('RWD')),
            DropdownMenuItem(value: 'awd', child: Text('AWD')),
            DropdownMenuItem(value: '4wd', child: Text('4WD')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('drv_$_specDropdownKey$value${constrained?.join() ?? 'full'}'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.driveType ?? 'Drive type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kDriveLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _driveType = v ?? _driveType;
          _syncCorrelatedFromOnlineVariants(
            {'drv'},
            drivetrain: _driveType,
          );
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _bodyTypeField(AppLocalizations? loc) {
    final constrained =
        _bodyTypeOptions != null && _bodyTypeOptions!.isNotEmpty
            ? _bodyTypeOptions!
            : null;
    final value =
        constrained != null ? _coerceInList(_bodyType, constrained) : _bodyType;
    final items = constrained != null
        ? constrained
            .map(
              (k) => DropdownMenuItem<String>(
                value: k,
                child: Text(_kBodyLabels[k] ?? k),
              ),
            )
            .toList()
        : const [
            DropdownMenuItem(value: 'sedan', child: Text('Sedan')),
            DropdownMenuItem(value: 'suv', child: Text('SUV')),
            DropdownMenuItem(value: 'hatchback', child: Text('Hatchback')),
            DropdownMenuItem(value: 'coupe', child: Text('Coupe')),
            DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
            DropdownMenuItem(value: 'van', child: Text('Van')),
          ];
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('body_$_specDropdownKey$value${constrained?.join() ?? 'full'}'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: loc?.bodyTypeLabel ?? 'Body type',
        helperText: constrained != null
            ? _labeledMultiHint(constrained, _kBodyLabels)
            : null,
      ),
      items: items,
      onChanged: (v) {
        setState(() {
          _bodyType = v ?? _bodyType;
          _syncCorrelatedFromOnlineVariants(
            {'body'},
            bodyType: _bodyType,
          );
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _engineSizeField() {
    final opts = _engineSizeDisplayOptions;
    if (opts != null && opts.isNotEmpty) {
      final pick = _coerceEngineDisplayPick(opts);
      return DropdownButtonFormField<String>(
        key: ValueKey<String>('es_${opts.join('|')}'),
        value: pick,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Engine size (L)',
          helperText: opts.length < 2 ? null : opts.join(' · '),
        ),
        items: opts
            .map(
              (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _engineSizeCtl.text = x;
            final lit = OnlineSpecVariant.parseLeadingEngineLiters(x);
            _syncCorrelatedFromOnlineVariants(
              {'e'},
              engineLiters: lit,
            );
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _engineSizeCtl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Engine size (L)',
      ),
    );
  }

  Widget _cylinderField() {
    final opts = _cylinderOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = int.tryParse(_cylinderCtl.text.trim());
      final value = (cur != null && opts.contains(cur)) ? cur : opts.first;
      return DropdownButtonFormField<int>(
        key: ValueKey<String>('cy_${opts.join(',')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Cylinders',
          helperText: opts.length < 2 ? null : opts.map((n) => '$n').join(' · '),
        ),
        items: opts
            .map(
              (n) => DropdownMenuItem<int>(
                value: n,
                child: Text('$n'),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants(
              {'c'},
              cylinders: x,
            );
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _cylinderCtl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Cylinders',
      ),
    );
  }

  Widget _fuelEconomyField() {
    final opts = _fuelEconomyOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = _fuelEconomyCtl.text.trim();
      final value = opts.contains(cur) ? cur : opts.first;
      return DropdownButtonFormField<String>(
        key: ValueKey<String>('mpg_${opts.join('|')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Fuel economy',
          helperText: opts.length < 2 ? null : '${opts.length} EPA values — pick one',
        ),
        items: opts
            .map(
              (s) => DropdownMenuItem<String>(
                value: s,
                child: Text(
                  s,
                  maxLines: 4,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants(
              {'mpg'},
              fuelEconomy: x,
            );
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _fuelEconomyCtl,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Fuel economy',
      ),
    );
  }

  Widget _seatingField() {
    final opts = _seatingOptions;
    if (opts != null && opts.isNotEmpty) {
      final cur = int.tryParse(_seatingCtl.text.trim());
      final value = (cur != null && opts.contains(cur)) ? cur : opts.first;
      return DropdownButtonFormField<int>(
        key: ValueKey<String>('seat_${opts.join(',')}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Seating',
          helperText: opts.length < 2 ? null : opts.map((n) => '$n').join(' · '),
        ),
        items: opts
            .map(
              (n) => DropdownMenuItem<int>(
                value: n,
                child: Text('$n'),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants(
              {'seat'},
              seating: x,
            );
          });
          _scheduleDraftSave();
        },
      );
    }
    return TextFormField(
      controller: _seatingCtl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Seating',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final modelList =
        (_selectedBrand != null) ? (CarCatalog.models[_selectedBrand!] ?? []) : <String>[];
    final trimList = CarCatalog.trimsFor(_selectedBrand, _selectedModel);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(loc?.sellTitle ?? 'Sell'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_submitting && (_stage ?? '').isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_stage!)),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(_error!),
                ),
                const SizedBox(height: 12),
              ],
              if (_specLoadError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Text(_specLoadError!),
                ),
                const SizedBox(height: 12),
              ],
              if (_draftLoaded && _draftExists) ...[
                Card(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _draftIsComplete
                              ? Icons.bookmark_added_outlined
                              : Icons.drafts_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Draft in progress',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _draftTitle(_draftPreviewData ?? _buildDraftData()),
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Continue here to finish the listing, or discard it if you want to start over.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _discardDraft,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Discard draft'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => unawaited(_resumeDraft()),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Continue'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                value: _selectedBrand,
                decoration: InputDecoration(labelText: loc?.brandLabel ?? 'Brand'),
                hint: Text(loc?.pleaseSelectBrand ?? 'Select brand'),
                items: CarCatalog.brands
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedBrand = v;
                    _selectedModel = null;
                    _selectedTrim = null;
                    _datasetModelId = null;
                    _catalogYear = null;
                    _clearCatalogExtraFields();
                  });
                  _scheduleRefreshDataset();
                  _scheduleDraftSave();
                },
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedModel,
                decoration: InputDecoration(labelText: loc?.modelLabel ?? 'Model'),
                hint: Text(loc?.selectBrandFirst ?? 'Select model'),
                items: modelList
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: _selectedBrand == null
                    ? null
                    : (v) {
                        setState(() {
                          _selectedModel = v;
                          _selectedTrim = null;
                          _datasetModelId = null;
                          _catalogYear = null;
                          _clearCatalogExtraFields();
                        });
                        _scheduleRefreshDataset();
                        _scheduleDraftSave();
                      },
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedTrim,
                decoration: const InputDecoration(labelText: 'Trim'),
                hint: const Text('Select trim'),
                items: trimList
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (_selectedBrand == null || _selectedModel == null)
                    ? null
                    : (v) {
                        setState(() {
                          _selectedTrim = v;
                          _datasetModelId = null;
                          _catalogYear = null;
                        });
                        _scheduleRefreshDataset();
                        _scheduleDraftSave();
                      },
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              _trimDependentCatalogSection(loc),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: loc?.yearLabel ?? 'Year'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n < 1980 || n > DateTime.now().year + 1) {
                          return loc?.invalidField ?? 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _mileage,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: loc?.mileageLabel ?? 'Mileage',
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n < 0) return loc?.invalidField ?? 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: loc?.priceLabel ?? 'Price'),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n <= 0) return loc?.invalidField ?? 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: InputDecoration(
                        labelText: loc?.currencyLabel ?? 'Currency',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'IQD', child: Text('IQD')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _currency = v);
                        _scheduleDraftSave();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _location,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: loc?.locationLabel ?? 'Location',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              _engineTypeField(loc),
              const SizedBox(height: 10),
              _transmissionField(loc),
              const SizedBox(height: 10),
              _driveTypeField(loc),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _condition,
                decoration: InputDecoration(labelText: loc?.conditionLabel ?? 'Condition'),
                items: const [
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'used', child: Text('Used')),
                ],
                onChanged: (v) {
                  setState(() => _condition = v ?? _condition);
                  _scheduleDraftSave();
                },
              ),
              const SizedBox(height: 10),
              _bodyTypeField(loc),
              const SizedBox(height: 10),
              Text(
                'Extra details (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Catalog fill writes here too. You can edit before submitting.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _engineSizeField()),
                  const SizedBox(width: 10),
                  Expanded(child: _cylinderField()),
                ],
              ),
              const SizedBox(height: 10),
              _fuelEconomyField(),
              const SizedBox(height: 10),
              _seatingField(),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: loc?.descriptionOptionalLabel ?? 'Description (optional)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        loc?.addPhotosCount(_images.length) ??
                            'Add photos (${_images.length})',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text(
                        loc?.addVideoCount(_videos.length) ??
                            'Add video (${_videos.length})',
                      ),
                    ),
                  ),
                ],
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final img = _images[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(img.path),
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 92,
                                height: 92,
                                color: Colors.black12,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: _submitting
                                  ? null
                                  : () {
                                      setState(() => _images.removeAt(index));
                                    },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting
                      ? (loc?.creatingListing ?? 'Creating listing...')
                      : (loc?.createListingButton ?? 'Create listing'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loc?.plateBlurNote ??
                    'Note: Plates are blurred only if you explicitly choose Blur Plates.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
