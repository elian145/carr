import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../data/car_catalog.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/car_specs_api_service.dart';
import '../services/auth_service.dart';
import '../services/car_spec_index.dart';
import '../services/ai_service.dart';
import '../services/ai_specs_normalizer.dart';

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
  bool _loadingOnlineSpecs = false;
  bool _loadingAiSpecs = false;
  String? _onlineSpecStatus;

  /// When online lookup finds 2+ distinct values, the matching field becomes a dropdown
  /// limited to these options (cleared when applying catalog specs).
  List<double>? _engineSizeLiterOptions;
  List<int>? _cylinderOptions;
  List<String>? _fuelEconomyOptions;
  List<int>? _seatingOptions;
  List<String>? _transmissionOptions;
  List<String>? _drivetrainOptions;
  List<String>? _bodyTypeOptions;
  List<String>? _engineTypeOptions;
  List<String>? _fuelTypeOptions;

  /// Populated after online lookup: paired engine size, cylinders, transmission, etc. per trim.
  List<OnlineSpecVariant>? _onlineSpecVariants;

  @override
  void initState() {
    super.initState();
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
    _engineSizeLiterOptions = null;
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

  void _refreshDatasetPicker() {
    final idx = _specIndex;
    final brand = _selectedBrand;
    final model = _selectedModel;
    final trim = _selectedTrim;

    int? newModelId = _datasetModelId;
    int? newYear = _catalogYear;

    if (idx == null ||
        brand == null ||
        model == null ||
        trim == null ||
        trim.trim().isEmpty ||
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
          var modelId = newModelId ?? 0;
          if (modelId == 0 || !variants.any((v) => v.id == modelId)) {
            modelId =
                idx.suggestDatasetModelId(bid, model, trim) ?? variants.first.id;
          }
          newModelId = modelId;
          final years = idx.yearsForModel(modelId);
          if (years.isEmpty) {
            newYear = null;
          } else if (newYear == null || !years.contains(newYear)) {
            newYear = years.first;
          }
        }
      }
    }

    setState(() {
      _datasetModelId = newModelId;
      _catalogYear = newYear;
    });
  }

  void _applyCatalogSpecs() {
    final idx = _specIndex;
    if (idx == null || _datasetModelId == null || _catalogYear == null) {
      return;
    }
    final fields = idx.appliedFieldsFor(_datasetModelId!, _catalogYear!);
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
    setState(() {
      _clearOnlineSpecOptionLists();
      _engineType = fields.engineType;
      _fuelType = fields.fuelType;
      _transmission = fields.transmission;
      _driveType = fields.driveType;
      _bodyType = fields.bodyType;
      _specDropdownKey++;
      _engineSizeCtl.text = fields.engineSizeLiters != null
          ? fields.engineSizeLiters!.toStringAsFixed(1)
          : '';
      _cylinderCtl.text =
          fields.cylinderCount != null ? '${fields.cylinderCount}' : '';
      _fuelEconomyCtl.text = fields.fuelEconomy ?? '';
      _seatingCtl.text = fields.seating != null ? '${fields.seating}' : '';
      _year.text = '${_catalogYear!}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Applied specs from catalog')),
    );
  }

  void _scheduleRefreshDataset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDatasetPicker();
    });
  }

  Future<void> _fetchOnlineSpecs() async {
    final brand = (_selectedBrand ?? '').trim();
    final model = (_selectedModel ?? '').trim();
    final trim = (_selectedTrim ?? '').trim();
    final year = int.tryParse(_year.text.trim());
    if (brand.isEmpty || model.isEmpty || trim.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select brand, model, and trim first'),
        ),
      );
      return;
    }
    if (year == null || year < 1980 || year > DateTime.now().year + 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid year before online spec lookup'),
        ),
      );
      return;
    }
    if (!CarSpecsApiService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CarSpecsApiService.missingConfigurationMessage),
        ),
      );
      return;
    }

    setState(() {
      _loadingOnlineSpecs = true;
      _onlineSpecStatus = null;
    });
    try {
      final specs = await CarSpecsApiService.lookupByYmm(
        year: year,
        brand: brand,
        model: model,
        trim: trim,
      );
      if (!mounted) return;
      setState(() {
        if (specs.engineType != null) _engineType = specs.engineType!;
        if (specs.fuelType != null) _fuelType = specs.fuelType!;
        if (specs.transmission != null) _transmission = specs.transmission!;
        if (specs.drivetrain != null) _driveType = specs.drivetrain!;
        if (specs.bodyType != null) _bodyType = specs.bodyType!;
        _specDropdownKey++;
        _engineSizeLiterOptions = specs.engineSizeLiterOptions;
        _cylinderOptions = specs.cylinderOptions;
        _fuelEconomyOptions = specs.fuelEconomyOptions;
        _seatingOptions = specs.seatingOptions;
        _transmissionOptions = specs.transmissionOptions;
        _drivetrainOptions = specs.drivetrainOptions;
        _bodyTypeOptions = specs.bodyTypeOptions;
        _engineTypeOptions = specs.engineTypeOptions;
        _fuelTypeOptions = specs.fuelTypeOptions;
        _onlineSpecVariants = specs.specVariants.isEmpty
            ? null
            : List<OnlineSpecVariant>.from(specs.specVariants);
        _engineSizeCtl.text = specs.engineSizeLiters != null
            ? specs.engineSizeLiters!.toStringAsFixed(1)
            : _engineSizeCtl.text;
        _cylinderCtl.text =
            specs.cylinderCount != null ? '${specs.cylinderCount}' : _cylinderCtl.text;
        _fuelEconomyCtl.text =
            specs.fuelEconomy != null ? specs.fuelEconomy! : _fuelEconomyCtl.text;
        _seatingCtl.text = specs.seating != null ? '${specs.seating}' : _seatingCtl.text;
        _syncConstrainedSelectionsAfterOnlineSpecs();
        _onlineSpecStatus =
            'Online specs applied for $brand $model $trim ($year).';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applied specs from online API')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _onlineSpecStatus = 'Online spec lookup failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Online spec lookup failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingOnlineSpecs = false);
      }
    }
  }

  void _applyAiSuggestedSpecs(Map<String, dynamic> specs) {
    final tr = AiSpecsNormalizer.transmissionApi(specs['transmission']);
    final drv = AiSpecsNormalizer.drivetrainApi(specs['drivetrain']);
    final body = AiSpecsNormalizer.bodyTypeApi(specs['body_type']);
    final fuel = AiSpecsNormalizer.fuelApi(specs['fuel_type'] ?? specs['engine_type']);
    final engt = AiSpecsNormalizer.fuelApi(specs['engine_type'] ?? fuel);
    final liters = AiSpecsNormalizer.engineLiters(specs['engine_size_liters']);
    final cyl = AiSpecsNormalizer.cylinders(specs['cylinder_count']);
    final seat = AiSpecsNormalizer.seating(specs['seating']);
    final fe = AiSpecsNormalizer.fuelEconomy(specs['fuel_economy']);
    final note = (specs['notes'] ?? '').toString().trim();

    setState(() {
      _clearOnlineSpecOptionLists();
      _specDropdownKey++;
      _transmission = tr;
      _driveType = drv;
      _bodyType = body;
      _fuelType = fuel;
      _engineType = engt;
      if (liters != null) {
        _engineSizeCtl.text = liters.toStringAsFixed(1);
      }
      _cylinderCtl.text = cyl != null ? '$cyl' : _cylinderCtl.text;
      if (fe != null) {
        _fuelEconomyCtl.text = fe;
      }
      _seatingCtl.text = seat != null ? '$seat' : _seatingCtl.text;
      _onlineSpecStatus = note.isEmpty
          ? 'AI suggestion applied — please verify before publishing.'
          : 'AI suggestion — please verify. $note';
    });
  }

  Future<void> _suggestSpecsWithAi() async {
    final brand = (_selectedBrand ?? '').trim();
    final model = (_selectedModel ?? '').trim();
    final trim = (_selectedTrim ?? '').trim();
    final year = int.tryParse(_year.text.trim());
    if (brand.isEmpty || model.isEmpty || trim.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select brand, model, and trim first'),
        ),
      );
      return;
    }
    if (year == null || year < 1980 || year > DateTime.now().year + 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid year first'),
        ),
      );
      return;
    }

    setState(() {
      _loadingAiSpecs = true;
      _onlineSpecStatus = null;
    });
    try {
      final raw = await AiService.suggestCarSpecsFromYmmRaw(
        year: year,
        brand: brand,
        model: model,
        trim: trim,
      );
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _onlineSpecStatus =
              'AI suggestion failed — check network and sign-in.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not get AI suggestion. Sign in and check your connection.',
            ),
          ),
        );
        return;
      }
      if (raw['error'] != null) {
        final msg = raw['error'].toString();
        setState(() => _onlineSpecStatus = msg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
      final specs = AiService.coerceJsonMap(raw['specs']);
      if (specs == null) {
        setState(() {
          _onlineSpecStatus = 'Invalid AI response from server.';
        });
        return;
      }
      _applyAiSuggestedSpecs(specs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'AI suggestion applied — review specs before submitting.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingAiSpecs = false);
    }
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
      final eng = double.tryParse(_engineSizeCtl.text.trim());
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc?.listingCreated ?? 'Listing created')),
      );
      Navigator.pushReplacementNamed(
        context,
        '/car_detail',
        arguments: {'carId': carId},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
                'You selected $brand $model. The bundled database only covers certain model lines (examples below). Pick one of those to unlock variant, year, and “Apply to form”.',
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

    final modelOk =
        _datasetModelId != null && variants.any((v) => v.id == _datasetModelId);
    if (!modelOk) {
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
                  'Loading catalog matches…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final years = idx.yearsForModel(_datasetModelId!);
    final preview = (_datasetModelId != null && _catalogYear != null)
        ? idx.appliedFieldsFor(_datasetModelId!, _catalogYear!)
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
              'Choose the catalog variant and year, then tap the button to copy values into the form below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (preview != null) ...[
              const SizedBox(height: 10),
              Text(
                'Will set: ${preview.engineType}, ${preview.transmission}, ${preview.driveType.toUpperCase()}, ${preview.bodyType}'
                '${preview.engineSizeLiters != null ? ', ${preview.engineSizeLiters!.toStringAsFixed(1)} L engine' : ''}'
                '${preview.cylinderCount != null ? ', ${preview.cylinderCount} cyl' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ] else if (_datasetModelId != null &&
                _catalogYear != null &&
                years.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'No spec row for this year — try another year or variant.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            if (variants.length > 1) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _datasetModelId,
                decoration: const InputDecoration(
                  labelText: 'Catalog variant',
                ),
                items: variants
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          v.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() {
                    _datasetModelId = id;
                    final ys = idx.yearsForModel(id);
                    _catalogYear = ys.isNotEmpty ? ys.first : null;
                  });
                },
              ),
            ],
            if (years.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
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
                },
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_datasetModelId != null &&
                      _catalogYear != null &&
                      preview != null &&
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
    final v = double.tryParse(_engineSizeCtl.text.trim());
    if (v == null) return null;
    return double.parse(v.toStringAsFixed(1));
  }

  double _coerceEngineLitersPick(List<double> opts) {
    final p = _parsedEngineLiters();
    if (p != null) {
      for (final o in opts) {
        if ((o - p).abs() < 0.06) return o;
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
      _engineSizeCtl.text = v.engineSizeLiters!.toStringAsFixed(1);
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

  /// After user changes one spec, align other fields to the matching Car API variant (if any).
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
      engineLiters: engineLiters,
      cylinders: cylinders,
      transmission: transmission,
      drivetrain: drivetrain,
      bodyType: bodyType,
      engineType: engineType,
      fuelType: fuelType,
      fuelEconomy: fe,
      seating: seating,
      currentTransmission: _transmission,
      currentDrivetrain: _driveType,
      currentSeating: int.tryParse(_seatingCtl.text.trim()),
    );
    if (m != null) {
      _applyOnlineVariantToForm(m);
      _specDropdownKey++;
    }
  }

  /// Keeps controllers / enum strings inside API option sets so submit matches the UI.
  void _syncConstrainedSelectionsAfterOnlineSpecs() {
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
    if (_engineSizeLiterOptions != null && _engineSizeLiterOptions!.isNotEmpty) {
      final opts = _engineSizeLiterOptions!;
      final p = double.tryParse(_engineSizeCtl.text.trim());
      final ok =
          p != null && opts.any((o) => (o - p).abs() < 0.06);
      if (!ok) {
        _engineSizeCtl.text = opts.first.toStringAsFixed(1);
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
      onChanged: (v) => setState(() {
        final nv = v ?? _engineType;
        _engineType = nv;
        _fuelType = nv;
        _syncCorrelatedFromOnlineVariants(
          {'engt', 'fuel'},
          engineType: nv,
          fuelType: nv,
        );
      }),
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
      onChanged: (v) => setState(() {
        _transmission = v ?? _transmission;
        _syncCorrelatedFromOnlineVariants(
          {'tr'},
          transmission: _transmission,
        );
      }),
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
      onChanged: (v) => setState(() {
        _driveType = v ?? _driveType;
        _syncCorrelatedFromOnlineVariants(
          {'drv'},
          drivetrain: _driveType,
        );
      }),
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
      onChanged: (v) => setState(() {
        _bodyType = v ?? _bodyType;
        _syncCorrelatedFromOnlineVariants(
          {'body'},
          bodyType: _bodyType,
        );
      }),
    );
  }

  Widget _engineSizeField() {
    final opts = _engineSizeLiterOptions;
    if (opts != null && opts.isNotEmpty) {
      final pick = _coerceEngineLitersPick(opts);
      return DropdownButtonFormField<double>(
        key: ValueKey<String>('es_${opts.join(',')}'),
        value: pick,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Engine size (L)',
          helperText: opts.length < 2
              ? null
              : opts.map((e) => e.toStringAsFixed(1)).join(' · '),
        ),
        items: opts
            .map(
              (e) => DropdownMenuItem<double>(
                value: e,
                child: Text(e.toStringAsFixed(1)),
              ),
            )
            .toList(),
        onChanged: (x) {
          if (x == null) return;
          setState(() {
            _syncCorrelatedFromOnlineVariants(
              {'e'},
              engineLiters: x,
            );
          });
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
                      },
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Online specs lookup',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Uses brand, model, trim, and year to fetch specs from API.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _loadingOnlineSpecs ||
                                _loadingAiSpecs ||
                                _submitting
                            ? null
                            : _fetchOnlineSpecs,
                        icon: _loadingOnlineSpecs
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          _loadingOnlineSpecs ? 'Fetching online specs…' : 'Fetch online specs',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _loadingOnlineSpecs ||
                                _loadingAiSpecs ||
                                _submitting
                            ? null
                            : _suggestSpecsWithAi,
                        icon: _loadingAiSpecs
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome_outlined),
                        label: Text(
                          _loadingAiSpecs
                              ? 'AI suggesting…'
                              : 'Suggest specs with AI (verify)',
                        ),
                      ),
                      if ((_onlineSpecStatus ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _onlineSpecStatus!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
                onChanged: (v) => setState(() => _condition = v ?? _condition),
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
