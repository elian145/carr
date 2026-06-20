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
import '../shared/auth/phone_verification_gate.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/prefs/sell_listing_draft_prefs.dart';
import '../shared/prefs/sell_draft_media_persistence.dart';
import '../shared/prefs/sell_draft_prefs.dart';


part 'sell/sell_page_draft.dart';
part 'sell/sell_page_catalog.dart';
part 'sell/sell_page_media.dart';
part 'sell/sell_page_submit.dart';
part 'sell/sell_page_catalog_ui.dart';
part 'sell/sell_page_fields.dart';

class SellPage extends StatefulWidget {
  const SellPage({
    super.key,
    this.initialDraftSnapshot,
    this.startFresh = false,
    this.editListing = false,
  });

  final Map<String, dynamic>? initialDraftSnapshot;
  final bool startFresh;
  final bool editListing;

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  final _formKey = GlobalKey<FormState>();

  String _text(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

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

  String _titleStatus = 'clean';
  final _damagedParts = TextEditingController();
  final _vin = TextEditingController();
  final List<XFile> _damageImages = <XFile>[];

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
  String? _editListingId;
  bool _skipDraftSaveOnDispose = false;

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
    _damagedParts.addListener(_onDraftFieldChanged);
    _vin.addListener(_onDraftFieldChanged);
    if (widget.startFresh) {
      unawaited(_startFreshFromRoute());
    } else if (widget.initialDraftSnapshot != null) {
      unawaited(_loadInitialDraftSnapshot(widget.initialDraftSnapshot!));
    } else {
      unawaited(_loadDraftPreview());
    }
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
    if (!_skipDraftSaveOnDispose) {
      unawaited(_saveDraft(immediate: true));
    }
    _year.removeListener(_onListingYearChanged);
    _mileage.removeListener(_onDraftFieldChanged);
    _price.removeListener(_onDraftFieldChanged);
    _location.removeListener(_onDraftFieldChanged);
    _description.removeListener(_onDraftFieldChanged);
    _engineSizeCtl.removeListener(_onDraftFieldChanged);
    _cylinderCtl.removeListener(_onDraftFieldChanged);
    _fuelEconomyCtl.removeListener(_onDraftFieldChanged);
    _seatingCtl.removeListener(_onDraftFieldChanged);
    _damagedParts.removeListener(_onDraftFieldChanged);
    _vin.removeListener(_onDraftFieldChanged);
    _year.dispose();
    _mileage.dispose();
    _price.dispose();
    _location.dispose();
    _description.dispose();
    _engineSizeCtl.dispose();
    _cylinderCtl.dispose();
    _fuelEconomyCtl.dispose();
    _seatingCtl.dispose();
    _damagedParts.dispose();
    _vin.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final modelList = (_selectedBrand != null)
        ? (CarCatalog.models[_selectedBrand!] ?? [])
        : <String>[];
    final trimList = CarCatalog.trimsFor(_selectedBrand, _selectedModel);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(loc?.sellTitle ?? 'Sell')),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
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
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _draftTitle(
                                  _draftPreviewData ?? _buildDraftData(),
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _text(
                                  'Continue here to finish the listing, or discard it if you want to start over.',
                                  ar: 'لەێرە بەردەوام بە بۆ تەواوکردنی لیستەکە، یان ئەگەر دەتەوێت لە نوێوە دەستپێبکەیت ڕەشنووسەکە بسڕەوە.',
                                  ku: 'لەێرە بەردەوام بە بۆ تەواوکردنی لیستەکە، یان ئەگەر دەتەوێت لە نوێوە دەستپێبکەیت ڕەشنووسەکە بسڕەوە.',
                                ),
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
                                    label: Text(
                                      _text(
                                        'Discard draft',
                                        ar: 'حذف المسودة',
                                        ku: 'سڕینەوەی ڕەشنووس',
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => unawaited(_resumeDraft()),
                                    icon: const Icon(Icons.play_arrow),
                                    label: Text(
                                      _text(
                                        'Continue',
                                        ar: 'متابعة',
                                        ku: 'بەردەوامبوون',
                                      ),
                                    ),
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
                decoration: InputDecoration(
                  labelText: loc?.brandLabel ?? 'Brand',
                ),
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
                validator: (v) => (v ?? '').trim().isEmpty
                    ? (loc?.requiredField ?? 'Required')
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedModel,
                decoration: InputDecoration(
                  labelText: loc?.modelLabel ?? 'Model',
                ),
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
                validator: (v) => (v ?? '').trim().isEmpty
                    ? (loc?.requiredField ?? 'Required')
                    : null,
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
                validator: (v) => (v ?? '').trim().isEmpty
                    ? (loc?.requiredField ?? 'Required')
                    : null,
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
                      decoration: InputDecoration(
                        labelText: loc?.yearLabel ?? 'Year',
                      ),
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
              TextFormField(
                controller: _vin,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: _text(
                    'VIN (optional)',
                    ar: 'رقم الهيكل (اختياري)',
                    ku: 'ژمارەی شاسی (ئارەزوومەندانە)',
                  ),
                  hintText: 'e.g. 1HGBH41JXMN109186',
                ),
                validator: (v) {
                  final trimmed = (v ?? '').trim();
                  if (trimmed.isEmpty) return null;
                  if (trimmed.length != 17) {
                    return _text(
                      'VIN must be 17 characters',
                      ar: 'رقم الهيكل يجب أن يكون 17 حرفاً',
                      ku: 'ژمارەی شاسی دەبێت ١٧ پیت بێت',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: loc?.priceLabel ?? 'Price',
                      ),
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
                validator: (v) => (v ?? '').trim().isEmpty
                    ? (loc?.requiredField ?? 'Required')
                    : null,
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
                decoration: InputDecoration(
                  labelText: loc?.conditionLabel ?? 'Condition',
                ),
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
              DropdownButtonFormField<String>(
                value: _titleStatus,
                decoration: InputDecoration(
                  labelText: loc?.titleStatus ?? 'Title status',
                ),
                items: [
                  DropdownMenuItem(
                    value: 'clean',
                    child: Text(loc?.value_title_clean ?? 'Clean'),
                  ),
                  DropdownMenuItem(
                    value: 'damaged',
                    child: Text(loc?.value_title_damaged ?? 'Damaged'),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) {
                        setState(() {
                          _titleStatus = v ?? 'clean';
                          if (_titleStatus == 'clean') {
                            _damagedParts.clear();
                            _damageImages.clear();
                          }
                        });
                        _scheduleDraftSave();
                      },
              ),
              if (_titleStatus == 'damaged') ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _damagedParts,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: loc?.damagedParts ?? 'Damaged parts',
                  ),
                ),
              ],
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
                  labelText:
                      loc?.descriptionOptionalLabel ?? 'Description (optional)',
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
                                    child: const Icon(
                                      Icons.image_not_supported,
                                    ),
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
              const SizedBox(height: 8),
              Text(
                loc?.damageCrashPhotosSection ??
                    'Damage / crash photos (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDamageImages,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  loc?.addDamagePhotosCount(_damageImages.length) ??
                      'Add damage photos (${_damageImages.length})',
                ),
              ),
              if (_damageImages.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _damageImages.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final img = _damageImages[index];
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
                                    child: const Icon(
                                      Icons.image_not_supported,
                                    ),
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
                                      setState(
                                        () => _damageImages.removeAt(index),
                                      );
                                      _scheduleDraftSave();
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
                      ? ((_editListingId ?? '').trim().isNotEmpty
                            ? 'Updating listing...'
                            : (loc?.creatingListing ?? 'Creating listing...'))
                      : ((_editListingId ?? '').trim().isNotEmpty
                            ? (loc?.saveChangesButton ?? 'Save changes')
                            : (loc?.createListingButton ?? 'Create listing')),
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
