part of 'main_legacy.dart';

const String _sellDraftArchiveKey = 'legacy_sell_draft_archive_v1';

String _newSellDraftId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Robust step index from JSON / route maps (`int`, `double`, `1.0` strings).
int _readSellDraftStepDynamic(dynamic raw, {int maxIdx = 4}) {
  if (raw == null) return 0;
  if (raw is int) return raw.clamp(0, maxIdx);
  if (raw is double) {
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.round().clamp(0, maxIdx);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return 0;
  final asDouble = double.tryParse(s);
  if (asDouble != null) {
    return asDouble.round().clamp(0, maxIdx);
  }
  return int.tryParse(s)?.clamp(0, maxIdx) ?? 0;
}

/// Prefer the higher of JSON snapshot step and prefs step when they disagree.
int _mergeSellDraftStep({int? jsonStep, int? prefsStep}) {
  const int maxIdx = 4;
  final j = (jsonStep ?? 0).clamp(0, maxIdx);
  if (prefsStep == null) return j;
  final p = prefsStep.clamp(0, maxIdx);
  return j > p ? j : p;
}

int _maxSellDraftStep(int a, int b, [int c = 0]) {
  const int maxIdx = 4;
  return math.max(math.max(a.clamp(0, maxIdx), b.clamp(0, maxIdx)), c.clamp(0, maxIdx));
}

Map<String, dynamic> _normalizeSellDraftSnapshot(Map<String, dynamic> raw) {
  final rawCarData = raw['carData'];
  final carData = rawCarData is Map
      ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
      : <String, dynamic>{};
  final draftId = (raw['draftId'] ?? '').toString().trim();
  return <String, dynamic>{
    'draftId': draftId.isEmpty ? _newSellDraftId() : draftId,
    'currentStep': _readSellDraftStepDynamic(raw['currentStep']),
    'carData': carData,
    'isPlaceholder': raw['isPlaceholder'] == true,
    'updatedAt': raw['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
  };
}

List<Map<String, dynamic>> _decodeSellDraftArchive(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map(
          (item) => _normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(item.cast<String, dynamic>()),
          ),
        )
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

String _encodeSellDraftArchive(List<Map<String, dynamic>> drafts) {
  return json.encode(
    drafts.map((draft) => _normalizeSellDraftSnapshot(draft)).toList(),
  );
}

bool _hasMeaningfulSellDraftValue(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is num) return value != 0;
  if (value is bool) return value;
  if (value is XFile) return value.path.trim().isNotEmpty;
  if (value is Map) {
    for (final entry in value.entries) {
      if (_hasMeaningfulSellDraftValue(entry.value)) return true;
    }
    return false;
  }
  if (value is Iterable) {
    for (final item in value) {
      if (_hasMeaningfulSellDraftValue(item)) return true;
    }
    return false;
  }
  return value.toString().trim().isNotEmpty;
}

bool _isVisibleSellDraft(Map<String, dynamic> draft) {
  return _hasMeaningfulSellDraftValue(draft['carData']);
}

class SellEntryRouterPage extends StatefulWidget {
  const SellEntryRouterPage({super.key});

  @override
  State<SellEntryRouterPage> createState() => _SellEntryRouterPageState();
}

class _SellEntryRouterPageState extends State<SellEntryRouterPage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _sellDraftArchiveKey = 'legacy_sell_draft_archive_v1';

  Future<void> _resolve() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
      bool hasAnyDraft = false;
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = _normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          hasAnyDraft = _isVisibleSellDraft(active);
        }
      }
      hasAnyDraft = hasAnyDraft || archive.any(_isVisibleSellDraft);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/sell',
        arguments: hasAnyDraft ? {'showDraftGate': true} : {'startFresh': true},
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/sell',
        arguments: {'startFresh': true},
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolve());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class SellDraftGatePage extends StatefulWidget {
  const SellDraftGatePage({super.key});

  @override
  State<SellDraftGatePage> createState() => _SellDraftGatePageState();
}

class _SellDraftGatePageState extends State<SellDraftGatePage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  bool _loading = true;
  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushReplacementNamed(context, '/');
    }
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

  Future<void> _loadDrafts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));

      final drafts = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(activeRaw);
          if (decoded is Map) {
            final active = _normalizeSellDraftSnapshot(
              Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
            );
            if (_isVisibleSellDraft(active)) {
              drafts.add(<String, dynamic>{...active, 'isActive': true});
              seenIds.add(active['draftId'].toString());
            }
          }
        } catch (_) {}
      }
      for (final draft in archive) {
        if (!_isVisibleSellDraft(draft)) continue;
        final id = draft['draftId'].toString();
        if (seenIds.contains(id)) continue;
        drafts.add(<String, dynamic>{...draft, 'isActive': false});
        seenIds.add(id);
      }

      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _loading = false;
      });
      if (_drafts.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_startFresh());
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _drafts = <Map<String, dynamic>>[];
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startFresh());
      });
    }
  }

  Future<void> _archiveActiveDraftIfAny({bool clearActive = true}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = _normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (_isVisibleSellDraft(active)) {
            final archive =
                _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
            archive.removeWhere((draft) => draft['draftId'] == active['draftId']);
            archive.insert(0, active);
            await sp.setString(
              _sellDraftArchiveKey,
              _encodeSellDraftArchive(archive),
            );
          }
        }
      }
      if (clearActive) {
        await sp.remove(_draftSnapshotKey);
        await sp.remove('legacy_sell_draft_current_step_v1');
        await sp.remove('legacy_sell_draft_step1_v1');
        await sp.remove('legacy_sell_draft_step2_v1');
        await sp.remove('legacy_sell_draft_step3_v1');
        await sp.remove('legacy_sell_draft_step4_v1');
      }
    } catch (_) {}
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final draftId = (draft['draftId'] ?? '').toString();
    final isActive = draft['isActive'] == true;
    try {
      final sp = await SharedPreferences.getInstance();
      if (isActive) {
        await sp.remove(_draftSnapshotKey);
        await sp.remove('legacy_sell_draft_current_step_v1');
        await sp.remove('legacy_sell_draft_step1_v1');
        await sp.remove('legacy_sell_draft_step2_v1');
        await sp.remove('legacy_sell_draft_step3_v1');
        await sp.remove('legacy_sell_draft_step4_v1');
      } else {
        final archive =
            _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
        archive.removeWhere((item) => item['draftId'] == draftId);
        await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
      }
      if (!mounted) return;
      setState(() {
        _drafts.removeWhere((item) => item['draftId'] == draftId);
      });
      if (_drafts.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_startFresh());
        });
      }
    } catch (_) {}
  }

  Future<void> _startFresh() async {
    LegacySellDraftPrefs.suppressPersist = true;
    await _archiveActiveDraftIfAny(clearActive: true);
    await LegacySellDraftPrefs.clearActiveStepStorage();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/sell',
      arguments: {'startFresh': true},
    );
  }

  Future<void> _startFreshWithArchive() async => _startFresh();

  Future<void> _continueDraft(Map<String, dynamic> draft) async {
    final normalized = _normalizeSellDraftSnapshot(draft);
    final isActive = draft['isActive'] == true;
    if (!isActive) {
      await _archiveActiveDraftIfAny(clearActive: false);
      try {
        final sp = await SharedPreferences.getInstance();
        final archive =
            _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
        archive.removeWhere((item) => item['draftId'] == normalized['draftId']);
        await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
        await sp.setString(_draftSnapshotKey, json.encode(normalized));
      } catch (_) {}
    }
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final fromNorm = _readSellDraftStepDynamic(normalized['currentStep']);
      final merged = _mergeSellDraftStep(jsonStep: fromNorm, prefsStep: prefsStep);
      normalized['currentStep'] = merged;
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/sell',
      arguments: {'draftSnapshot': normalized},
    );
  }

  Widget _buildDraftCard(Map<String, dynamic> draft) {
    final carData = draft['carData'] is Map
        ? Map<String, dynamic>.from((draft['carData'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final currentStep = _readSellDraftStepDynamic(draft['currentStep']);
    final labels = <String>[
      _trLegacyText(context, 'Step 1: Basic info', ar: 'الخطوة 1: المعلومات الأساسية', ku: 'هەنگاو 1: زانیاری سەرەکی'),
      _trLegacyText(context, 'Step 2: Details', ar: 'الخطوة 2: التفاصيل', ku: 'هەنگاو 2: وردەکاری'),
      _trLegacyText(context, 'Step 3: Pricing', ar: 'الخطوة 3: السعر', ku: 'هەنگاو 3: نرخ'),
      _trLegacyText(context, 'Step 4: Photos', ar: 'الخطوة 4: الصور', ku: 'هەنگاو 4: وێنەکان'),
      _trLegacyText(context, 'Step 5: Review', ar: 'الخطوة 5: المراجعة', ku: 'هەنگاو 5: پێداچوونەوە'),
    ];
    final label = labels[currentStep.clamp(0, 4).toInt()];
    final title = _draftTitle(carData);
    final isActive = draft['isActive'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withOpacity(0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.drafts_outlined, color: Color(0xFFFF6B00)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive
                            ? _trLegacyText(
                                context,
                                'Draft in progress',
                                ar: 'مسودة قيد التقدم',
                                ku: 'ڕەشنووسی لە پێشکەوتن',
                              )
                            : _trLegacyText(
                                context,
                                'Saved draft',
                                ar: 'مسودة محفوظة',
                                ku: 'ڕەشنووسی پارێزراو',
                              ),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              _trLegacyText(
                context,
                'Continue, discard, or start a new listing without deleting this draft.',
                ar: 'أكمل أو احذف أو ابدأ إعلانا جديدا بدون حذف هذه المسودة.',
                ku: 'بەردەوام بە یان بسڕەوە یان ڕیکلامێکی نوێ دەستپێبکە بێ سڕینەوەی ئەم ڕەشنووسە.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _continueDraft(draft),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _trLegacyText(
                        context,
                        'Continue',
                        ar: 'متابعة',
                        ku: 'بەردەوام بە',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _discardDraft(draft),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      _trLegacyText(
                        context,
                        'Discard',
                        ar: 'حذف',
                        ku: 'بسڕەوە',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDrafts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addListingTitle),
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_drafts.isEmpty)
              ? Center(
                  child: ElevatedButton(
                    onPressed: () => unawaited(_startFresh()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      _trLegacyText(
                        context,
                        'Start new listing',
                        ar: 'ابدأ إعلانا جديدا',
                        ku: 'ڕیکلامێکی نوێ دەستپێبکە',
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.orange.withOpacity(0.24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trLegacyText(
                              context,
                              'Drafts in progress',
                              ar: 'مسودات قيد التقدم',
                              ku: 'ڕەشنووسەکان لە پێشکەوتندان',
                            ),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _trLegacyText(
                              context,
                              'Continue any draft, discard one, or start a new listing while keeping the others.',
                              ar: 'تابع أي مسودة أو احذف واحدة أو ابدأ إعلانا جديدا مع الاحتفاظ بالباقي.',
                              ku: 'هەر ڕەشنووسێک بەردەوام پێبدە یان یەکێک بسڕەوە یان ڕیکلامێکی نوێ دەستپێبکە لەگەڵ پاراستنی ئەوانی تر.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._drafts.map(_buildDraftCard),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => unawaited(_startFreshWithArchive()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _trLegacyText(
                            context,
                            'Start new listing',
                            ar: 'ابدأ إعلانا جديدا',
                            ku: 'ڕیکلامێکی نوێ دەستپێبکە',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// Multi-step sell page
class SellCarPage extends StatefulWidget {
  const SellCarPage({
    super.key,
    this.initialDraftSnapshot,
    this.startFreshListing = false,
  });

  final Map<String, dynamic>? initialDraftSnapshot;
  final bool startFreshListing;

  @override
  _SellCarPageState createState() => _SellCarPageState();
}

class _SellCarPageState extends State<SellCarPage> {
  int currentStep = 0;
  late final PageController _pageController;
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  bool _hasDraftSnapshot = false;
  bool _hideDraftBanner = false;
  int _draftPreviewStep = 0;
  Map<String, dynamic>? _draftPreviewCarData;
  int _sellPageResetToken = 0;
  int _draftResumeToken = 0;
  String _currentDraftId = _newSellDraftId();
  bool _skipDraftPersistOnDispose = false;
  String? _editListingId;

  bool get _isEditMode => (_editListingId ?? '').trim().isNotEmpty;

  // Car data that will be passed between steps
  Map<String, dynamic> carData = {};

  // Track completed steps
  Set<int> completedSteps = {};

  static const int _kSellStepCount = 5;

  /// Step 2 key bumps when catalog specs are applied so Car Details reloads from [carData].
  Widget _sellStepChild(int index) {
    if (index == 4) {
      return SellStep5Page(key: ValueKey(_step5ImagesKey));
    }
    switch (index) {
      case 0:
        return SellStep1Page(
          resumeDraftToken: _draftResumeToken,
          key: ValueKey('s1_${_draftResumeToken}'),
        );
      case 1:
        return SellStep2Page(
          key: ValueKey(
            's2_${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}_${carData['brand']}_${carData['model']}_${carData['trim']}_${carData['year']}',
          ),
          specsHydrateToken:
              '${carData['_catalog_specs_applied'] ?? 0}_${carData['_online_specs_applied'] ?? 0}',
        );
      case 2:
        return const SellStep3Page();
      case 3:
        return const SellStep4Page();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Key that changes when carData images/videos change so Step 5 (summary) rebuilds.
  String get _step5ImagesKey {
    final imgs = carData['images'];
    final vids = carData['videos'];
    final dmg = carData['damage_images'];
    final dmgPart = (dmg == null || dmg is! List || dmg.isEmpty)
        ? ''
        : dmg.map((e) => e is XFile ? e.path : e.toString()).join('|');
    final imgPart = (imgs == null || imgs is! List || imgs.isEmpty)
        ? ''
        : imgs.map((e) => e is XFile ? e.path : e.toString()).join('|');
    final vidPart = (vids == null || vids is! List || vids.isEmpty)
        ? ''
        : vids.map((e) => e is XFile ? e.path : e.toString()).join('|');
    if (imgPart.isEmpty && vidPart.isEmpty && dmgPart.isEmpty) return '0';
    return '$imgPart::$vidPart::$dmgPart';
  }

  Future<void> _restoreDraftCurrentStep() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final saved = sp.getInt(_draftCurrentStepKey);
      if (saved == null) return;
      final clamped = saved.clamp(0, _kSellStepCount - 1);
      if (!mounted) return;
      setState(() {
        currentStep = clamped;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(clamped);
        }
      });
    } catch (_) {}
  }

  /// Non-empty field check for draft persistence (aligned with step sync keys).
  bool _sellPersistFieldNonEmpty(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is num) return true;
    if (v is bool) return v;
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return v.toString().trim().isNotEmpty;
  }

  /// Highest wizard index (0–4) that already has saved field data.
  /// Used so "Back" from step 2 to step 1 does not persist [currentStep] = 0
  /// while car details (e.g. transmission) remain in [carData].
  int _deepestSellWizardStepHintFromCarData() {
    final d = carData;
    int maxIdx = 0;
    if (_sellPersistFieldNonEmpty(d['mileage']) ||
        _sellPersistFieldNonEmpty(d['condition']) ||
        _sellPersistFieldNonEmpty(d['transmission']) ||
        _sellPersistFieldNonEmpty(d['fuel_type']) ||
        _sellPersistFieldNonEmpty(d['body_type']) ||
        _sellPersistFieldNonEmpty(d['color']) ||
        _sellPersistFieldNonEmpty(d['drive_type']) ||
        _sellPersistFieldNonEmpty(d['region_specs']) ||
        _sellPersistFieldNonEmpty(d['seating']) ||
        _sellPersistFieldNonEmpty(d['engine_size']) ||
        _sellPersistFieldNonEmpty(d['cylinder_count']) ||
        _sellPersistFieldNonEmpty(d['title_status']) ||
        _sellPersistFieldNonEmpty(d['damaged_parts'])) {
      maxIdx = 1;
    }
    if (_sellPersistFieldNonEmpty(d['price']) ||
        _sellPersistFieldNonEmpty(d['city']) ||
        _sellPersistFieldNonEmpty(d['contact_phone']) ||
        _sellPersistFieldNonEmpty(d['plate_type']) ||
        _sellPersistFieldNonEmpty(d['plate_city']) ||
        _sellPersistFieldNonEmpty(d['description'])) {
      maxIdx = math.max(maxIdx, 2);
    }
    final imgs = d['images'];
    if (imgs is List && imgs.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    final dmg = d['damage_images'];
    if (dmg is List && dmg.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    final vids = d['videos'];
    if (vids is List && vids.isNotEmpty) {
      maxIdx = math.max(maxIdx, 3);
    }
    return maxIdx.clamp(0, _kSellStepCount - 1);
  }

  int _effectivePersistedDraftStep() {
    return math
        .max(currentStep, _deepestSellWizardStepHintFromCarData())
        .clamp(0, _kSellStepCount - 1);
  }

  Future<void> _saveDraftCurrentStep() async {
    if (_isEditMode) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_draftCurrentStepKey, _effectivePersistedDraftStep());
    } catch (_) {}
  }

  Future<void> _clearDraftCurrentStep() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_draftCurrentStepKey);
    } catch (_) {}
  }

  Future<void> _initFreshListingSession() async {
    await LegacySellDraftPrefs.clearActiveStepStorage();
    LegacySellDraftPrefs.allowPersist();
    if (!mounted) return;
    setState(() {
      _sellPageResetToken++;
    });
  }

  Future<void> _clearAllSellDrafts() async {
    try {
      _skipDraftPersistOnDispose = true;
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_draftCurrentStepKey);
      await sp.remove(_draftSnapshotKey);
      await sp.remove(_sellDraftArchiveKey);
      await LegacySellDraftPrefs.clearActiveStorage();
      if (mounted) {
        setState(() {
          carData = <String, dynamic>{};
          _hasDraftSnapshot = false;
          _currentDraftId = _newSellDraftId();
        });
      }
    } catch (_) {}
  }

  Future<void> _clearSubmittedDraftOnly({String? draftId}) async {
    try {
      _skipDraftPersistOnDispose = true;
      final sp = await SharedPreferences.getInstance();
      final String resolvedDraftId =
          (draftId ?? _currentDraftId).toString().trim();

      await sp.remove(_draftCurrentStepKey);
      await sp.remove(_draftSnapshotKey);
      await sp.remove('legacy_sell_draft_step1_v1');
      await sp.remove('legacy_sell_draft_step2_v1');
      await sp.remove('legacy_sell_draft_step3_v1');
      await sp.remove('legacy_sell_draft_step4_v1');

      if (resolvedDraftId.isNotEmpty) {
        final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
        archive.removeWhere(
          (item) => item['draftId']?.toString() == resolvedDraftId,
        );
        await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
      }

      if (mounted) {
        setState(() {
          carData = <String, dynamic>{};
          _hasDraftSnapshot = false;
          _currentDraftId = _newSellDraftId();
        });
      }
    } catch (_) {}
  }

  Future<void> _seedFreshDraftPlaceholder() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final placeholder = _normalizeSellDraftSnapshot(<String, dynamic>{
        'draftId': _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
        'currentStep': 0,
        'carData': <String, dynamic>{},
        'isPlaceholder': true,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      _currentDraftId = placeholder['draftId'].toString();
      await sp.setString(_draftSnapshotKey, json.encode(placeholder));
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
      archive.removeWhere((item) => item['draftId'] == placeholder['draftId']);
      archive.insert(0, placeholder);
      await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
      if (mounted) {
        setState(() {
          _hasDraftSnapshot = true;
          _draftPreviewStep = 0;
          _draftPreviewCarData = const <String, dynamic>{};
        });
      }
    } catch (_) {}
  }

  dynamic _draftValue(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is XFile) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _draftValue(v)));
    }
    if (value is Iterable) {
      return value.map(_draftValue).toList();
    }
    return value.toString();
  }

  bool _hasMeaningfulDraftValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num) return value != 0;
    if (value is bool) return value;
    if (value is XFile) return value.path.trim().isNotEmpty;
    if (value is Map) {
      for (final entry in value.entries) {
        if (_hasMeaningfulDraftValue(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_hasMeaningfulDraftValue(item)) return true;
      }
      return false;
    }
    return value.toString().trim().isNotEmpty;
  }

  Future<void> _saveSellDraftSnapshot() async {
    if (_isEditMode) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final hasExistingSnapshot =
          (sp.getString(_draftSnapshotKey)?.trim().isNotEmpty == true);
      if (!_hasMeaningfulDraftValue(carData)) {
        if (hasExistingSnapshot) {
          if (mounted) {
            setState(() {
              _hasDraftSnapshot = true;
            });
          }
          return;
        }
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        await LegacySellDraftPrefs.clearActiveStepStorage();
        if (mounted) {
          setState(() {
            _hasDraftSnapshot = false;
          });
        }
        return;
      }
      final persistedStep = _effectivePersistedDraftStep();
      final storedCarData =
          await SellDraftMediaPersistence.prepareCarDataForStorage(
        carData,
        draftId: _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
      );
      if (mounted) {
        setState(() {
          carData = storedCarData;
        });
      } else {
        carData = storedCarData;
      }
      final snapshot = <String, dynamic>{
        'draftId': _currentDraftId.isNotEmpty ? _currentDraftId : _newSellDraftId(),
        'currentStep': persistedStep,
        'carData': _draftValue(storedCarData),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _currentDraftId = snapshot['draftId'].toString();
      await sp.setString(
        _draftSnapshotKey,
        json.encode(snapshot),
      );
      await sp.setInt(_draftCurrentStepKey, persistedStep);
      final archive = _decodeSellDraftArchive(sp.getString(_sellDraftArchiveKey));
      archive.removeWhere((draft) => draft['draftId'] == _currentDraftId);
      archive.insert(0, snapshot);
      await sp.setString(_sellDraftArchiveKey, _encodeSellDraftArchive(archive));
    } catch (_) {}
  }

  Future<void> _restoreSellDraftSnapshot() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final jsonStep = _readSellDraftStepDynamic(data['currentStep']);
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final restoredStep = _mergeSellDraftStep(
        jsonStep: jsonStep,
        prefsStep: prefsStep,
      );
      _currentDraftId = (data['draftId'] ?? _newSellDraftId()).toString();
      final rawCarData = data['carData'];
      final restoredCarData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      final isPlaceholder = data['isPlaceholder'] == true;
      if (!_hasMeaningfulDraftValue(restoredCarData) && !isPlaceholder) {
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        currentStep = restoredStep.clamp(0, _kSellStepCount - 1);
        carData = _resolveCarDataMedia(restoredCarData);
        _hasDraftSnapshot = true;
        _draftPreviewStep = currentStep;
        _draftPreviewCarData = carData;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(currentStep);
        }
      });
    } catch (_) {}
  }

  Future<void> _resumeSellDraft() async {
    setState(() {
      _draftResumeToken++;
    });
    await _restoreSellDraftSnapshot();
  }

  Future<void> _reconcileSellStepWithPrefsAfterDraftOpen() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      int fromDisk = currentStep;
      final raw = sp.getString(_draftSnapshotKey);
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final m = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
            fromDisk = _readSellDraftStepDynamic(m['currentStep']);
          }
        } catch (_) {}
      }
      final merged = _maxSellDraftStep(
        currentStep,
        fromDisk,
        prefsStep ?? 0,
      );
      if (merged == currentStep) return;
      setState(() {
        currentStep = merged;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(currentStep);
        }
      });
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
    } catch (_) {}
  }

  Map<String, dynamic> _resolveCarDataMedia(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    for (final key in ['images', 'damage_images', 'videos']) {
      if (copy[key] is List) {
        copy[key] = SellDraftMediaPersistence.resolveDynamicMediaList(
          List<dynamic>.from(copy[key] as List),
        );
      }
    }
    return copy;
  }

  void _applyDraftSnapshot(
    Map<String, dynamic> snapshot, {
    bool restoreCurrentStep = true,
  }) {
    final currentStepValue = _readSellDraftStepDynamic(snapshot['currentStep']);
    final rawCarData = snapshot['carData'];
    final restoredCarData = rawCarData is Map
        ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
        : <String, dynamic>{};
    final isPlaceholder = snapshot['isPlaceholder'] == true;
    if (!_hasMeaningfulDraftValue(restoredCarData) && !isPlaceholder) return;
    _currentDraftId = (snapshot['draftId'] ?? _newSellDraftId()).toString();
    final editId = (restoredCarData['_editListingId'] ?? '').toString().trim();
    if (editId.isNotEmpty) {
      _editListingId = editId;
      _skipDraftPersistOnDispose = true;
    }

    if (restoreCurrentStep) {
      currentStep = currentStepValue.clamp(0, _kSellStepCount - 1);
    }
    carData = _resolveCarDataMedia(restoredCarData);
    _hasDraftSnapshot = true;
    _draftPreviewStep = currentStep;
    _draftPreviewCarData = carData;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(currentStep);
      }
    });
  }

  Future<void> _loadSellDraftPreview() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftSnapshotKey);
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
          _draftPreviewStep = 0;
          _draftPreviewCarData = null;
        });
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final restoredStep = _readSellDraftStepDynamic(data['currentStep']);
      final rawCarData = data['carData'];
      final restoredCarData = rawCarData is Map
          ? Map<String, dynamic>.from(rawCarData.cast<String, dynamic>())
          : <String, dynamic>{};
      if (!_hasMeaningfulDraftValue(restoredCarData)) {
        await sp.remove(_draftCurrentStepKey);
        await sp.remove(_draftSnapshotKey);
        if (!mounted) return;
        setState(() {
          _hasDraftSnapshot = false;
          _draftPreviewStep = 0;
          _draftPreviewCarData = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _hasDraftSnapshot = true;
        _draftPreviewStep = restoredStep.clamp(0, _kSellStepCount - 1);
        _draftPreviewCarData = restoredCarData;
      });
    } catch (_) {}
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

  Widget _buildDraftBanner() {
    if (!_hasDraftSnapshot || _hideDraftBanner) {
      return const SizedBox.shrink();
    }
    final labels = <String>[
      'Step 1: Basic info',
      'Step 2: Details',
      'Step 3: Pricing',
      'Step 4: Photos',
      'Step 5: Review',
    ];
    final stepLabel = labels[_draftPreviewStep.clamp(0, 4).toInt()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.drafts_outlined, color: Color(0xFFFF6B00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _trLegacyText(
                            context,
                            'Draft in progress',
                            ar: 'مسودة قيد التقدم',
                            ku: 'ڕەشنووسی لە پێشکەوتن',
                          ),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(stepLabel, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _draftTitle(_draftPreviewCarData ?? carData),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Continue here to finish the listing, or discard it if you want to start over.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _clearAllSellDrafts();
                        if (!mounted) return;
                        setState(() {
                          currentStep = 0;
                          carData = {};
                          completedSteps.clear();
                          _hasDraftSnapshot = false;
                          _draftPreviewStep = 0;
                          _draftPreviewCarData = null;
                          _sellPageResetToken++;
                        });
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(0);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard draft'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => unawaited(_resumeSellDraft()),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continue'),
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

  @override
  void initState() {
    super.initState();
    int controllerInitialPage = 0;
    final initialDraft = widget.initialDraftSnapshot;
    if (initialDraft != null) {
      controllerInitialPage =
          _readSellDraftStepDynamic(initialDraft['currentStep'])
              .clamp(0, _kSellStepCount - 1);
    }
    _pageController = PageController(initialPage: controllerInitialPage);
    if (initialDraft != null) {
      _hideDraftBanner = true;
      _currentDraftId = (initialDraft['draftId'] ?? _newSellDraftId()).toString();
      _applyDraftSnapshot(initialDraft);
      unawaited(_reconcileSellStepWithPrefsAfterDraftOpen());
      // Some builds align [PageView] after layout; force the visible page once attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          final t = currentStep.clamp(0, _kSellStepCount - 1);
          final cur = _pageController.page?.round();
          if (cur != t) {
            _pageController.jumpToPage(t);
          }
        });
      });
    } else if (widget.startFreshListing) {
      _hideDraftBanner = true;
      _hasDraftSnapshot = false;
      _draftPreviewStep = 0;
      _draftPreviewCarData = null;
      _currentDraftId = _newSellDraftId();
      carData = <String, dynamic>{};
      completedSteps.clear();
      currentStep = 0;
      unawaited(_initFreshListingSession());
    } else {
      unawaited(_loadSellDraftPreview());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _goToPreviousStep();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _isEditMode
                ? AppLocalizations.of(context)!.editListingTitle
                : AppLocalizations.of(context)!.addListingTitle,
          ),
          backgroundColor: Color(0xFFFF6B00),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: _goToPreviousStep,
          ),
        ),
        body: Container(
          decoration: AppThemes.shellBackgroundDecoration(
            Theme.of(context).brightness,
          ),
          child: Column(
            children: [
              if (!_isEditMode) _buildDraftBanner(),
              // Progress indicator
              Container(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: List.generate(5, (index) {
                    bool isCompleted = completedSteps.contains(index);
                    bool isCurrent = index == currentStep;
                    bool isAccessible = index <= currentStep || isCompleted;

                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 4),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green
                              : isCurrent
                              ? Color(0xFFFF6B00)
                              : isAccessible
                              ? Color(0xFFFF6B00).withOpacity(0.5)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Step indicator
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.stepXOf5(currentStep + 1),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _getStepTitle(context, currentStep),
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFFF6B00),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Page content
              Expanded(
                child: PageView.builder(
                  key: ValueKey(_sellPageResetToken),
                  controller: _pageController,
                  physics:
                      NeverScrollableScrollPhysics(), // Disable swipe scrolling
                  // Do not persist from [onPageChanged]: during [nextPage] the
                  // callback can report page 0 and race async saves, overwriting
                  // the real step (e.g. user on step 2). Step is saved from
                  // [_goToNextStep]/[_goToPreviousStep], field syncs, and [dispose].
                  itemCount: _kSellStepCount,
                  itemBuilder: (context, index) => _sellStepChild(index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepTitle(BuildContext context, int step) {
    final l = AppLocalizations.of(context)!;
    switch (step) {
      case 0:
        return l.basicInformationTitle;
      case 1:
        return l.carDetailsTitle;
      case 2:
        return l.pricingContactTitle;
      case 3:
        return l.photosVideosTitle;
      case 4:
        return l.reviewSubmitTitle;
      default:
        return '';
    }
  }

  // Method to validate if a step is completed
  bool _isStepCompleted(int step) {
    switch (step) {
      case 0: // Basic Information
        return carData['brand'] != null &&
            carData['brand'].toString().isNotEmpty &&
            carData['model'] != null &&
            carData['model'].toString().isNotEmpty &&
            carData['trim'] != null &&
            carData['trim'].toString().isNotEmpty &&
            carData['year'] != null &&
            carData['year'].toString().isNotEmpty;
      case 1: // Car Details
        return carData['mileage'] != null &&
            carData['mileage'].toString().isNotEmpty &&
            carData['condition'] != null &&
            carData['condition'].toString().isNotEmpty &&
            carData['transmission'] != null &&
            carData['transmission'].toString().isNotEmpty &&
            carData['fuel_type'] != null &&
            carData['fuel_type'].toString().isNotEmpty &&
            carData['body_type'] != null &&
            carData['body_type'].toString().isNotEmpty &&
            carData['color'] != null &&
            carData['color'].toString().isNotEmpty &&
            carData['seating'] != null &&
            carData['seating'].toString().isNotEmpty &&
            carData['drive_type'] != null &&
            carData['drive_type'].toString().isNotEmpty &&
            carData['region_specs'] != null &&
            carData['region_specs'].toString().trim().isNotEmpty &&
            isValidCarRegionSpecCode(
              carData['region_specs'].toString().trim().toLowerCase(),
            ) &&
            carData['title_status'] != null &&
            carData['title_status'].toString().isNotEmpty;
      case 2: // Pricing & Contact
        return carData['city'] != null &&
            carData['city'].toString().isNotEmpty &&
            carData['contact_phone'] != null &&
            carData['contact_phone'].toString().isNotEmpty;
      case 3: // Photos & Videos
        return carData['images'] != null &&
            (carData['images'] as List).isNotEmpty;
      case 4: // Review & Submit
        return true; // This step is always accessible for review
      default:
        return false;
    }
  }

  // Method to navigate to next step with validation
  void _goToNextStep() {
    if (currentStep < _kSellStepCount - 1) {
      if (_isStepCompleted(currentStep)) {
        completedSteps.add(currentStep);
        setState(() {
          currentStep++;
        });
        unawaited(_saveDraftCurrentStep());
        unawaited(_saveSellDraftSnapshot());
        _pageController.nextPage(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please complete all required fields before proceeding',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Method to navigate to previous step
  void _goToPreviousStep() {
    if (currentStep > 0) {
      setState(() {
        currentStep--;
      });
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // Bottom nav uses pushReplacementNamed to open Sell, so there is no
      // route below us — pop would show an empty/black screen.
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  /// Jump to a wizard index and keep [currentStep] + persisted draft in sync
  /// (used e.g. when validation sends the user back to a specific step).
  void _jumpSellWizardToIndex(int index) {
    final clamped = index.clamp(0, _kSellStepCount - 1);
    setState(() {
      currentStep = clamped;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(clamped);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(clamped);
        }
      });
    }
    unawaited(_saveDraftCurrentStep());
    unawaited(_saveSellDraftSnapshot());
  }

  @override
  void dispose() {
    if (!_skipDraftPersistOnDispose &&
        !LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraftCurrentStep());
      unawaited(_saveSellDraftSnapshot());
    }
    _pageController.dispose();
    super.dispose();
  }
}

// Step 1: Basic Information (Brand, Model, Trim, Year)
class SellStep1Page extends StatefulWidget {
  const SellStep1Page({super.key, this.resumeDraftToken = 0});

  final int resumeDraftToken;

  @override
  _SellStep1PageState createState() => _SellStep1PageState();
}

class _SellStep1PageState extends State<SellStep1Page> {
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

  String _brandSlug(String brand) {
    String s = brand.toLowerCase().trim();
    const replacements = {
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã¢': 'a',
      'Ã¤': 'a',
      'Ã£': 'a',
      'Ã¥': 'a',
      'Ã©': 'e',
      'Ã¨': 'e',
      'Ãª': 'e',
      'Ã«': 'e',
      'Ã­': 'i',
      'Ã¬': 'i',
      'Ã®': 'i',
      'Ã¯': 'i',
      'Ã³': 'o',
      'Ã²': 'o',
      'Ã´': 'o',
      'Ã¶': 'o',
      'Ãµ': 'o',
      'Ã¸': 'o',
      'Ãº': 'u',
      'Ã¹': 'u',
      'Ã»': 'u',
      'Ã¼': 'u',
      'Ã½': 'y',
      'Ã¿': 'y',
      'Ã±': 'n',
      'Ã§': 'c',
      'Ä': 'c',
      'Ä‡': 'c',
      'Å¡': 's',
      'ÃŸ': 'ss',
      'Å¾': 'z',
      'Å“': 'oe',
      'Ã¦': 'ae',
      'Ä‘': 'd',
      'Å‚': 'l',
    };
    replacements.forEach((k, v) {
      s = s.replaceAll(k, v);
    });
    s = s.replaceAll(RegExp(r"[^a-z0-9]+"), '-');
    s = s.replaceAll(RegExp(r"-+"), '-').replaceAll(RegExp(r"(^-|-$)"), '');
    return s;
  }

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController();
    _yearController.addListener(_onYearTextForCatalog);
    _resetSellFilters();
    _hydrateFromParentCarData();
    CarSpecIndex.loadWithResult().then((r) {
      if (!mounted) return;
      setState(() {
        _specIdx = r.index;
        _specLoadErr = r.errorMessage;
        _specDbReady = true;
        _pruneYearOutsideCatalog();
      });
      _schedDsRefresh();
    });
  }

  @override
  void didUpdateWidget(covariant SellStep1Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resumeDraftToken != oldWidget.resumeDraftToken ||
        widget.resumeDraftToken > 0) {
      _hydrateFromParentCarData();
    }
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _yearFocusNode.dispose();
    _yearController.removeListener(_onYearTextForCatalog);
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      if (!mounted) return;
      setState(() {
        selectedBrand = data['selectedBrand']?.toString();
        selectedModel = data['selectedModel']?.toString();
        selectedTrim = data['selectedTrim']?.toString();
        selectedYear = data['selectedYear']?.toString();
        errBrand = data['errBrand'] == true;
        errModel = data['errModel'] == true;
        errTrim = data['errTrim'] == true;
        errYear = data['errYear'] == true;
        isYearManualInput = data['isYearManualInput'] == true;
        _dsModelId = int.tryParse(data['dsModelId']?.toString() ?? '');
        _catYear = int.tryParse(data['catYear']?.toString() ?? '');
        _yearController.text = data['yearControllerText']?.toString() ?? '';
      });
      _schedDsRefresh();
    } catch (_) {}
  }

  void _hydrateFromParentCarData() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final data = parent?.carData;
    if (data == null || data.isEmpty) return;
    setState(() {
      selectedBrand = data['brand']?.toString();
      selectedModel = data['model']?.toString();
      selectedTrim = data['trim']?.toString();
      selectedYear = data['year']?.toString();
      _dsModelId = int.tryParse(data['_catalog_model_id']?.toString() ?? '');
      _catYear = int.tryParse(data['_catalog_year']?.toString() ?? '');
      final yearText = data['year']?.toString() ?? '';
      _yearController.text = yearText;
    });
  }

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _draftKey,
        json.encode(<String, dynamic>{
          'selectedBrand': selectedBrand,
          'selectedModel': selectedModel,
          'selectedTrim': selectedTrim,
          'selectedYear': selectedYear,
          'errBrand': errBrand,
          'errModel': errModel,
          'errTrim': errTrim,
          'errYear': errYear,
          'isYearManualInput': isYearManualInput,
          'dsModelId': _dsModelId,
          'catYear': _catYear,
          'yearControllerText': _yearController.text,
        }),
      );
    } catch (_) {}
  }

  Future<void> _resetSellFilters() async {
    selectedBrand = null;
    selectedModel = null;
    selectedTrim = null;
    selectedYear = null;
    setState(() {});
  }

  void _dismissKeyboard() {
    // Clear focus from year field
    _yearFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _schedDsRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDsPicker();
    });
  }

  void _onYearTextForCatalog() {
    _schedDsRefresh();
  }

  void _resetDsPicker() {
    _dsModelId = null;
    _catYear = null;
  }

  void _refreshDsPicker() {
    final idx = _specIdx;
    final b = selectedBrand;
    final m = selectedModel;
    int? newId = _dsModelId;
    int? newY = _catYear;
    if (idx == null || b == null || m == null || !idx.hasCoverage(b, m)) {
      newId = null;
      newY = null;
    } else {
      final bid = idx.datasetBrandId(b);
      if (bid == null) {
        newId = null;
        newY = null;
      } else {
        final variants = idx.variantsForAppModel(b, m);
        if (variants.isEmpty) {
          newId = null;
          newY = null;
        } else {
          final formYear =
              int.tryParse(_yearController.text.trim()) ??
              int.tryParse((selectedYear ?? '').trim());
          final years = idx.yearsForCatalogStep(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
          );
          if (years.isEmpty) {
            newId = null;
            newY = null;
          } else {
            int resolvedYear;
            if (formYear != null && years.contains(formYear)) {
              resolvedYear = formYear;
            } else if (newY != null && years.contains(newY)) {
              resolvedYear = newY;
            } else {
              resolvedYear = years.first;
            }
            newY = resolvedYear;
            final preferred = idx.suggestDatasetModelIdForFormYear(
              b,
              m,
              CarSpecIndex.catalogAutofillModelOnly,
              resolvedYear,
            );
            var mid = newId ?? 0;
            if (mid == 0 || !variants.any((v) => v.id == mid)) {
              mid = preferred ?? variants.first.id;
            } else if (!idx.datasetVariantCoversYear(mid, resolvedYear)) {
              mid = preferred ?? mid;
            }
            newId = mid;
          }
        }
      }
    }
    setState(() {
      _dsModelId = newId;
      _catYear = newY;
      _pruneYearOutsideCatalog();
    });
  }

  /// Catalog-backed years for the current brand + model, or null to use the default range.
  List<String>? _catalogYearStringsIfAny() {
    final idx = _specIdx;
    final b = selectedBrand;
    final m = selectedModel;
    if (idx == null || b == null || m == null) {
      return null;
    }
    if (!idx.hasCoverage(b, m)) return null;
    final ys = idx.yearsForCatalogStep(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
    );
    if (ys.isEmpty) return null;
    return ys.map((e) => '$e').toList();
  }

  void _pruneYearOutsideCatalog() {
    if (isYearManualInput) return;
    final catalog = _catalogYearStringsIfAny();
    if (catalog == null) return;
    if (selectedYear != null && !catalog.contains(selectedYear)) {
      selectedYear = null;
    }
  }

  void _syncStep1DraftToParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    parent.carData['brand'] = selectedBrand;
    parent.carData['model'] = selectedModel;
    parent.carData['trim'] = selectedTrim;
    parent.carData['year'] = selectedYear;
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
  }

  void _applyCatalogSpecsToFlow() {
    final idx = _specIdx;
    if (idx == null || _catYear == null) return;
    final b = (selectedBrand ?? '').trim();
    final m = (selectedModel ?? '').trim();
    if (b.isEmpty || m.isEmpty) return;
    final rep = idx.representativeForCatalogSell(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
      _catYear!,
    );
    final CatalogSpecFields? f = rep?.fields;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No spec row for this year — try another year or variant.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    _clearOnlineSpecOptionsInCarData(parent.carData);
    final y = '${_catYear!}';
    setState(() {
      if (rep != null) {
        _dsModelId = rep.datasetModelId;
      }
      selectedYear = y;
      if (isYearManualInput) {
        _yearController.text = y;
      }
    });
    parent.carData['transmission'] = sellFlowTransmissionLabel(f.transmission);
    parent.carData['fuel_type'] = sellFlowFuelLabel(f.fuelType);
    parent.carData['engine_type'] = f.engineType;
    parent.carData['body_type'] = sellFlowBodyLabel(f.bodyType);
    parent.carData['drive_type'] = sellFlowDriveLabel(f.driveType);
    if (f.engineSizeLiters != null && f.engineSizeLiters! > 0) {
      // Keep suffix (T/D/TD) for display, while the API submit parses leading liters.
      parent.carData['engine_size'] =
          '${f.engineSizeLiters!.toStringAsFixed(1)}${f.displacementSuffix}';
    }
    if (f.cylinderCount != null && f.cylinderCount! > 0) {
      parent.carData['cylinder_count'] = '${f.cylinderCount}';
    }
    final seatStr = sellFlowNearestSeatingLabel(f.seating);
    if (seatStr != null) {
      parent.carData['seating'] = seatStr;
    }
    if (f.fuelEconomy != null && f.fuelEconomy!.trim().isNotEmpty) {
      parent.carData['fuel_economy'] = f.fuelEconomy!.trim();
    }
    final union = (b.isNotEmpty && m.isNotEmpty)
        ? idx.sellFieldOptionsUnion(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
            _catYear!,
          )
        : null;
    var catVs = (b.isNotEmpty && m.isNotEmpty)
        ? idx.catalogSellSpecVariants(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
            _catYear!,
          )
        : const <OnlineSpecVariant>[];
    if (catVs.isEmpty) {
      catVs = [_onlineSpecVariantFromCatalogFields(f)];
    }
    if (union != null) {
      _applyCatalogSellFieldUnionToCarData(parent.carData, union);
    } else {
      _applyCatalogSpecConstrainedOptionsToCarData(parent.carData, f);
    }
    if (catVs.isNotEmpty) {
      parent.carData[_kOnlineSpecVariantsKey] = catVs
          .map((e) => e.toJson())
          .toList();
    }
    parent.carData['_catalog_specs_applied'] =
        DateTime.now().millisecondsSinceEpoch;
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _trLegacyText(
            context,
            'Specs applied — year set; step 2 fields pre-filled.',
            ar: 'تم تطبيق المواصفات — تم ضبط السنة وملء حقول الخطوة 2 مسبقا.',
            ku: 'سپێسەکان جێبەجێ کران — ساڵ دانرا و خانەکانی هەنگاو 2 پڕکرانەوە.',
          ),
        ),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  Widget _buildTrimCatalogSection() {
    final trim = (selectedTrim ?? '').trim();
    if (trim.isEmpty) return const SizedBox.shrink();
    final b = selectedBrand;
    final m = selectedModel;
    if (b == null || m == null) return const SizedBox.shrink();

    if (!_specDbReady) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                  _trLegacyText(
                    context,
                    'Loading vehicle spec database...',
                    ar: 'جاري تحميل قاعدة بيانات مواصفات السيارة...',
                    ku: 'بنکەی زانیاری سپێسی ئۆتۆمبێل بار دەکرێت...',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_specIdx == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _specLoadErr ??
                _trLegacyText(
                  context,
                  'Spec database unavailable. Run a full app restart after flutter pub get.',
                  ar: 'قاعدة بيانات المواصفات غير متاحة. أعد تشغيل التطبيق بالكامل بعد flutter pub get.',
                  ku: 'بنکەی زانیاری سپێس بەردەست نییە. دوای flutter pub get ئەپەکە بە تەواوی دووبارە بکەرەوە.',
                ),
          ),
        ),
      );
    }
    if (!_specIdx!.hasCoverage(b, m)) {
      final hints = _specIdx!.catalogCoverageHints();
      final sample = hints.take(12).join(' · ');
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _trLegacyText(
                  context,
                  'No catalog auto-fill for this vehicle',
                  ar: 'لا يوجد تعبئة تلقائية من الكتالوج لهذه السيارة',
                  ku: 'پڕکردنەوەی خۆکار لە کاتالۆگ بۆ ئەم ئۆتۆمبێلە نییە',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _trLegacyText(
                  context,
                  'You selected $b $m. This build only includes some lines in the bundled file, e.g.:',
                  ar: 'لقد اخترت $b $m. هذا الإصدار يحتوي فقط على بعض السطور في الملف المدمج، مثلا:',
                  ku: 'تۆ $b $m هەڵبژارد. ئەم وەشانە تەنها هەندێک هێڵ لە پەڕگەی هاوپێکراودا هەیە، بۆ نموونە:',
                ),
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              if (sample.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  sample,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final idx = _specIdx!;
    final variants = idx.variantsForAppModel(b, m);
    if (variants.isEmpty) return const SizedBox.shrink();

    final listingYear =
        int.tryParse(_yearController.text.trim()) ??
        int.tryParse((selectedYear ?? '').trim());
    final years = idx.yearsForCatalogStep(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
    );
    if (years.isEmpty) return const SizedBox.shrink();

    final CatalogSpecFields? preview = _catYear != null
        ? idx
              .representativeForCatalogSell(
                b,
                m,
                CarSpecIndex.catalogAutofillModelOnly,
                _catYear!,
              )
              ?.fields
        : null;
    final unionPreview = _catYear != null
        ? idx.sellFieldOptionsUnion(
            b,
            m,
            CarSpecIndex.catalogAutofillModelOnly,
            _catYear!,
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _trLegacyText(
                context,
                'Catalog auto-fill',
                ar: 'تعبئة تلقائية من الكتالوج',
                ku: 'پڕکردنەوەی خۆکاری کاتالۆگ',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              listingYear != null
                  ? _trLegacyText(
                      context,
                      'Pick catalog year and apply. Step 2 lists every engine and spec row we have for this model—choose what matches your car.',
                      ar: 'اختر سنة الكتالوج ثم طبّق. الخطوة 2 تعرض كل خيارات المحرك والمواصفات لهذا الموديل — اختر ما يناسب سيارتك.',
                      ku: 'ساڵی کاتالۆگ هەڵبژێرە و جێبەجێی بکە. هەنگاوی 2 هەموو هەڵبژاردەکانی مەکینە و سپێس بۆ ئەم مۆدێلە پیشان دەدات — ئەوە هەڵبژێرە کە لەگەڵ ئۆتۆمبێلەکەت دەگونجێت.',
                    )
                  : _trLegacyText(
                      context,
                      'Enter or pick a year above, choose catalog year, then apply. Step 2 is where you pick engine and other specs.',
                      ar: 'أدخل أو اختر سنة بالأعلى، ثم اختر سنة الكتالوج وبعدها طبّق. في الخطوة 2 تختار المحرك وباقي المواصفات.',
                      ku: 'لە سەرەوە ساڵ بنووسە یان هەڵیبژێرە، پاشان ساڵی کاتالۆگ هەڵبژێرە و جێبەجێی بکە. لە هەنگاوی 2 مەکینە و سپێسی تر هەڵدەبژێریت.',
                    ),
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            if (preview != null || unionPreview != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B00).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF6B00).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  () {
                    var engExtra = '';
                    if (unionPreview != null &&
                        unionPreview.engineSizes.length > 1) {
                      final engList = unionPreview.engineSizes.toList()
                        ..sort(
                          (a, b) => (double.tryParse(a) ?? 0).compareTo(
                            double.tryParse(b) ?? 0,
                          ),
                        );
                      engExtra =
                          '\n${_trLegacyText(context, 'Step 2 will offer engines:', ar: 'الخطوة 2 ستعرض المحركات:', ku: 'هەنگاوی 2 ئەم مەکینانە پیشان دەدات:')} ${engList.join(', ')} L';
                    }
                    if (preview != null) {
                      return '${_trLegacyText(context, 'Preview (smallest engine in list — change in step 2 if needed):', ar: 'معاينة (أصغر محرك في القائمة — يمكنك تغييره في الخطوة 2 إذا لزم):', ku: 'پێشبینین (بچووکترین مەکینە لە لیستەکە — دەتوانیت لە هەنگاوی 2 بیگۆڕیت ئەگەر پێویست بوو):')} ${_translateValueGlobal(context, preview.engineType) ?? preview.engineType}, ${_translateValueGlobal(context, preview.transmission) ?? preview.transmission}, ${_translateValueGlobal(context, preview.driveType) ?? preview.driveType}, ${_translateValueGlobal(context, preview.bodyType) ?? preview.bodyType}$engExtra';
                    }
                    return '${_trLegacyText(context, 'This year has catalog coverage — apply to load step 2 options (engine, cylinders, etc.).', ar: 'هذه السنة مدعومة في الكتالوج — طبّق لتحميل خيارات الخطوة 2 (المحرك، الأسطوانات، إلخ).', ku: 'ئەم ساڵە پشتگیری کاتالۆگی هەیە — جێبەجێ بکە بۆ بارکردنی هەڵبژاردەکانی هەنگاوی 2 (مەکینە، سیلەندەر، هتد).')}$engExtra';
                  }(),
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: Color(0xFFFF6B00),
                  ),
                ),
              ),
            ],
            if (years.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _catYear != null && years.contains(_catYear)
                    ? _catYear
                    : years.first,
                decoration: InputDecoration(
                  labelText: _trLegacyText(
                    context,
                    'Model year',
                    ar: 'سنة الموديل',
                    ku: 'ساڵی مۆدێل',
                  ),
                ),
                items: years
                    .map(
                      (y) => DropdownMenuItem<int>(value: y, child: Text('$y')),
                    )
                    .toList(),
                onChanged: (y) {
                  if (y == null) return;
                  setState(() => _catYear = y);
                  _schedDsRefresh();
                },
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (preview == null && unionPreview == null)
                  ? null
                  : _applyCatalogSpecsToFlow,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(
                _trLegacyText(
                  context,
                  'Apply specs to listing',
                  ar: 'تطبيق المواصفات على الإعلان',
                  ku: 'سپێسەکان بخرە ناو ڕیکلامەکە',
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickFromList(
    String title,
    List<String> options, {
    String? contextBrand,
  }) async {
    services.HapticFeedback.selectionClick();
    String query = '';
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final loc = AppLocalizations.of(context)!;
            final isYearPicker =
                title == loc.yearLabel || title.toLowerCase().contains('year');
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = options.where((value) {
              if (isYearPicker) return true;
              if (normalizedQuery.isEmpty) return true;
              if (value.toLowerCase().contains(normalizedQuery)) return true;
              if (contextBrand != null) {
                final locModel = CarNameTranslations.getLocalizedModel(
                  context,
                  contextBrand,
                  value,
                ).toLowerCase();
                if (locModel.contains(normalizedQuery)) return true;
              }
              final locBrand = CarNameTranslations.getLocalizedBrand(
                context,
                value,
              ).toLowerCase();
              if (locBrand.contains(normalizedQuery)) return true;
              final translated = (_translateValueGlobal(context, value) ?? '')
                  .toLowerCase();
              return translated.contains(normalizedQuery);
            }).toList();
            return Dialog(
              backgroundColor: Colors.grey[900]?.withOpacity(0.98),
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
                    if (!isYearPicker) ...[
                      TextField(
                        onChanged: (value) {
                          query = value;
                          setStateDialog(() {});
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _trLegacyText(
                            context,
                            'Search...',
                            ar: 'بحث...',
                            ku: 'گەڕان...',
                          ),
                          hintStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white70,
                          ),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 400,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final value = filtered[index];
                          final lowerTitle = title.toLowerCase();
                          final loc = AppLocalizations.of(context)!;
                          final isModelTitle = title == loc.modelLabel;
                          final isTrimTitle = title == loc.trimLabel;
                          final isBrandTitle = title == loc.brandLabel;
                          String displayText = value;
                          final bool isNumeric = RegExp(
                            r'^[0-9]+(\.[0-9]+)?$',
                          ).hasMatch(value);
                          if (lowerTitle.contains('price')) {
                            displayText = _formatCurrencyGlobal(context, value);
                          } else if (lowerTitle.contains('mileage') &&
                              isNumeric) {
                            final nf = _decimalFormatterGlobal(context);
                            displayText =
                                '${_localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0))} ${AppLocalizations.of(context)!.unit_km}';
                          } else if (lowerTitle.contains('year') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value);
                          } else if (lowerTitle.contains('seating') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}';
                          } else if (lowerTitle.contains('cylinder') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}';
                          } else if (lowerTitle.contains('region') &&
                              isValidCarRegionSpecCode(value)) {
                            displayText =
                                carRegionSpecDisplayLabelLocalized(context, value);
                          } else if (lowerTitle.contains('engine') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} L';
                          } else if (value == 'Any') {
                            displayText = AppLocalizations.of(
                              context,
                            )!.anyOption;
                          } else if (isModelTitle && contextBrand != null) {
                            displayText =
                                CarNameTranslations.getLocalizedModel(
                                  context,
                                  contextBrand,
                                  value,
                                ).isNotEmpty
                                ? CarNameTranslations.getLocalizedModel(
                                    context,
                                    contextBrand,
                                    value,
                                  )
                                : value;
                          } else if (isTrimTitle) {
                            displayText = value;
                          } else if (isBrandTitle) {
                            displayText =
                                CarNameTranslations.getLocalizedBrand(
                                  context,
                                  value,
                                ).isNotEmpty
                                ? CarNameTranslations.getLocalizedBrand(
                                    context,
                                    value,
                                  )
                                : value;
                          } else {
                            final translated = _translateValueGlobal(
                              context,
                              value,
                            );
                            if (translated != null) displayText = translated;
                          }
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
                                    Colors.white.withOpacity(0.06),
                                    Colors.white.withOpacity(0.02),
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
                                      displayText,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                  ),
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
      },
    );
  }

  Future<String?> _pickBrandModal() async {
    String query = '';
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final normalizedQuery = query.trim().toLowerCase();
            final filteredBrands = brands.where((brand) {
              if (normalizedQuery.isEmpty) return true;
              if (brand.toLowerCase().contains(normalizedQuery)) return true;
              final localized = CarNameTranslations.getLocalizedBrand(
                context,
                brand,
              ).toLowerCase();
              return localized.contains(normalizedQuery);
            }).toList();
            return Dialog(
              backgroundColor: Colors.grey[900]?.withOpacity(0.98),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 480,
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.selectBrand,
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
                    TextField(
                      onChanged: (value) {
                        query = value;
                        setStateDialog(() {});
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          hintText: _trLegacyText(
                            context,
                            'Search...',
                            ar: 'بحث...',
                            ku: 'گەڕان...',
                          ),
                        hintStyle: const TextStyle(color: Colors.white60),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white70,
                        ),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.2),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFFF6B00),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 420,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: filteredBrands.length,
                        itemBuilder: (context, index) {
                          final brand = filteredBrands[index];
                          final logoFile = _brandSlug(brand);
                          final logoUrl =
                              '${getApiBase()}/static/images/brands/$logoFile.png';
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, brand),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              padding: EdgeInsets.all(6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: logoUrl,
                                      placeholder: (context, url) => SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Image.network(
                                            '${getApiBase()}/static/images/brands/default.png',
                                            fit: BoxFit.contain,
                                          ),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    CarNameTranslations.getLocalizedBrand(
                                          context,
                                          brand,
                                        ).isNotEmpty
                                        ? CarNameTranslations.getLocalizedBrand(
                                            context,
                                            brand,
                                          )
                                        : brand,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
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
      },
    );
  }

  List<String> get brands => CarCatalog.brands;
  Map<String, List<String>> get models => CarCatalog.models;
  Map<String, Map<String, List<String>>> get trimsByBrandModel =>
      CarCatalog.trimsByBrandModel;

  List<String> get availableYears {
    final catalog = _catalogYearStringsIfAny();
    if (catalog != null) return catalog;
    final currentYear = DateTime.now().year;
    return List.generate(30, (index) => (currentYear - index).toString());
  }

  List<String> get availableTrims =>
      CarCatalog.trimsFor(selectedBrand, selectedModel);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.directions_car,
                    size: 48,
                    color: Color(0xFFFF6B00),
                  ),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.basicInformationTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.basicInformationSubtitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Brand Selection (Modal)
            FormField<String>(
              validator: (_) => selectedBrand == null
                  ? AppLocalizations.of(context)!.pleaseSelectBrand
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickBrandModal();
                  if (choice != null) {
                    setState(() {
                      selectedBrand = choice;
                      selectedModel = null;
                      selectedTrim = null;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  label: '${AppLocalizations.of(context)!.brandLabel} *',
                  value: selectedBrand != null
                      ? (CarNameTranslations.getLocalizedBrand(
                              context,
                              selectedBrand,
                            ).isNotEmpty
                            ? CarNameTranslations.getLocalizedBrand(
                                context,
                                selectedBrand,
                              )
                            : selectedBrand)
                      : selectedBrand,
                  isError:
                      errBrand &&
                      (selectedBrand == null || selectedBrand!.isEmpty),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B00).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: selectedBrand == null
                        ? Icon(Icons.business, color: const Color(0xFFFF6B00))
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: CachedNetworkImage(
                              imageUrl:
                                  '${getApiBase()}/static/images/brands/${_brandSlug(selectedBrand!)}.png',
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) => Image.network(
                                '${getApiBase()}/static/images/brands/default.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Model (Modal)
            FormField<String>(
              validator: (_) => selectedModel == null
                  ? AppLocalizations.of(context)!.pleaseSelectModel
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  if (selectedBrand == null) return;
                  final options = models[selectedBrand!] ?? [];
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.modelLabel,
                    options,
                    contextBrand: selectedBrand,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedModel = choice;
                      selectedTrim = null;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions_car,
                  label: '${AppLocalizations.of(context)!.modelLabel} *',
                  value: selectedModel != null
                      ? (CarNameTranslations.getLocalizedModel(
                              context,
                              selectedBrand,
                              selectedModel,
                            ).isNotEmpty
                            ? CarNameTranslations.getLocalizedModel(
                                context,
                                selectedBrand,
                                selectedModel,
                              )
                            : selectedModel)
                      : (selectedBrand == null
                            ? AppLocalizations.of(context)!.selectBrandFirst
                            : ''),
                  isError:
                      errModel &&
                      (selectedModel == null || selectedModel!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Trim (Modal)
            FormField<String>(
              validator: (_) => selectedTrim == null
                  ? AppLocalizations.of(context)!.pleaseSelectTrim
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.trimLabel,
                    availableTrims,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTrim = choice;
                      _resetDsPicker();
                      _pruneYearOutsideCatalog();
                    });
                    _schedDsRefresh();
                    _syncStep1DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings,
                  label: '${AppLocalizations.of(context)!.trimLabel} *',
                  value: selectedTrim,
                  isError:
                      errTrim &&
                      (selectedTrim == null || selectedTrim!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            _buildTrimCatalogSection(),

            // Year (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isYearManualInput
                      ? TextFormField(
                          focusNode: _yearFocusNode,
                          controller: _yearController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.yearLabel} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.enterYearHint,
                            filled: true,
                            fillColor: _sellFlowManualFieldFill(context),
                            labelStyle: _sellFlowManualFieldLabelStyle(context),
                            hintStyle: _sellFlowManualFieldHintStyle(context),
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
                          onChanged: (value) {
                            setState(() {
                              selectedYear = value.isEmpty ? null : value;
                            });
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseEnterYear;
                            }
                            final year = int.tryParse(value);
                            if (year == null) return l.yearInvalid;
                            if (year < 1900 || year > DateTime.now().year + 1) {
                              return l.yearOutOfRange;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) => selectedYear == null
                              ? AppLocalizations.of(context)!.pleaseSelectYear
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.yearLabel,
                                availableYears,
                              );
                              if (choice != null) {
                                setState(() {
                                  selectedYear = choice;
                                });
                                _syncStep1DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.calendar_today,
                              label:
                                  '${AppLocalizations.of(context)!.yearLabel} *',
                              value: selectedYear != null
                                  ? _localizeDigitsGlobal(
                                      context,
                                      selectedYear!,
                                    )
                                  : null,
                              isError:
                                  errYear &&
                                  (selectedYear == null ||
                                      selectedYear!.isEmpty),
                            ),
                          ),
                        ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isYearManualInput) {
                      // If in manual input mode, confirm the year and dismiss keyboard
                      _yearFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isYearManualInput = false;
                        // Ensure the selectedYear is properly set
                        if (_yearController.text.isNotEmpty) {
                          selectedYear = _yearController.text;
                        }
                      });
                      _syncStep1DraftToParent();
                    } else {
                      // If in dropdown mode, switch to manual input
                      setState(() {
                        isYearManualInput = true;
                        // Clear the controller to start fresh
                        _yearController.clear();
                        selectedYear = null;
                      });
                      _syncStep1DraftToParent();
                    }
                  },
                  icon: Icon(
                    isYearManualInput ? Icons.check : Icons.edit,
                    color: Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isYearManualInput
                      ? AppLocalizations.of(context)!.confirmYear
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
            SizedBox(height: 32),

            // Next Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Manual validation for required selectors (since we use custom tiles)
                  final List<String> missing = [];
                  if (selectedBrand == null || (selectedBrand ?? '').isEmpty) {
                    missing.add(AppLocalizations.of(context)!.brandLabel);
                  }
                  if (selectedModel == null || (selectedModel ?? '').isEmpty) {
                    missing.add(AppLocalizations.of(context)!.modelLabel);
                  }
                  if (selectedTrim == null || (selectedTrim ?? '').isEmpty) {
                    missing.add(AppLocalizations.of(context)!.trimLabel);
                  }
                  if (selectedYear == null || (selectedYear ?? '').isEmpty) {
                    missing.add(AppLocalizations.of(context)!.yearLabel);
                  }

                  if (missing.isNotEmpty) {
                    setState(() {
                      errBrand =
                          selectedBrand == null ||
                          (selectedBrand ?? '').isEmpty;
                      errModel =
                          selectedModel == null ||
                          (selectedModel ?? '').isEmpty;
                      errTrim =
                          selectedTrim == null || (selectedTrim ?? '').isEmpty;
                      errYear =
                          selectedYear == null || (selectedYear ?? '').isEmpty;
                    });
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

                  // Save data and navigate to next step
                  final parentState = context
                      .findAncestorStateOfType<_SellCarPageState>();
                  if (parentState != null) {
                    parentState.carData['brand'] = selectedBrand;
                    parentState.carData['model'] = selectedModel;
                    parentState.carData['trim'] = selectedTrim;
                    parentState.carData['year'] = selectedYear;
                    setState(() {
                      errBrand = errModel = errTrim = errYear = false;
                    });
                    parentState._goToNextStep();
                    unawaited(parentState._saveSellDraftSnapshot());
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Step 2: Car Details (Mileage, Condition, Transmission, etc.)
class SellStep2Page extends StatefulWidget {
  const SellStep2Page({super.key, this.specsHydrateToken = ''});

  /// When catalog/online/AI specs timestamps change, state re-reads [carData] (covers off-screen step 2).
  final String specsHydrateToken;

  @override
  _SellStep2PageState createState() => _SellStep2PageState();
}

class _SellStep2PageState extends State<SellStep2Page> {
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

  @override
  void initState() {
    super.initState();
    _mileageController = TextEditingController();
    _engineSizeController = TextEditingController();
    _vinController = TextEditingController();
    _resetStep2();
    _hydrateFromParentCarData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hydrateFromParentCarData(force: true);
    });
    CarSpecIndex.load().then((idx) {
      if (!mounted) return;
      setState(() {
        _specIdx = idx;
        _refreshCatalogOptsFromParent();
      });
    });
  }

  @override
  void didUpdateWidget(covariant SellStep2Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.specsHydrateToken != oldWidget.specsHydrateToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hydrateFromParentCarData(force: true);
      });
    }
  }

  CatalogSellFieldOptions? _computeCatalogSellOpts(
    Map<String, dynamic>? carData,
    CarSpecIndex? idx,
  ) {
    if (carData == null || idx == null) return null;
    final b = carData['brand']?.toString().trim() ?? '';
    final m = carData['model']?.toString().trim() ?? '';
    final y = int.tryParse(carData['year']?.toString().trim() ?? '');
    if (b.isEmpty || m.isEmpty || y == null) return null;
    if (!idx.hasCoverage(b, m)) return null;
    return idx.sellFieldOptionsUnion(
      b,
      m,
      CarSpecIndex.catalogAutofillModelOnly,
      y,
    );
  }

  void _refreshCatalogOptsFromParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    _catalogSellOpts = _computeCatalogSellOpts(parent?.carData, _specIdx);
  }

  void _hydrateFromParentCarData({bool force = false}) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    _refreshCatalogOptsFromParent();
    if (parent == null) return;

    final rawCatalog = parent.carData['_catalog_specs_applied'];
    final rawOnline = parent.carData['_online_specs_applied'];
    final catalogStamp = rawCatalog is int
        ? rawCatalog
        : int.tryParse(rawCatalog?.toString() ?? '');
    final onlineStamp = rawOnline is int
        ? rawOnline
        : int.tryParse(rawOnline?.toString() ?? '');
    int? stamp;
    for (final x in [catalogStamp, onlineStamp]) {
      if (x == null) continue;
      if (stamp == null || x > stamp) stamp = x;
    }

    if (!force) {
      if (stamp == null || stamp == _lastSpecsHydrateStamp) return;
    } else if (stamp == null) {
      // Force hydration from parent snapshot even without explicit stamp.
      // This covers first-time step open when values are already in carData.
    }

    _lastSpecsHydrateStamp = stamp ?? _lastSpecsHydrateStamp;
    final d = parent.carData;
    void take(String key, void Function(String v) apply) {
      final v = d[key]?.toString().trim();
      if (v != null && v.isNotEmpty) apply(v);
    }

    void takeScalarOrOnlineOpt(
      String scalarKey,
      String optKey,
      void Function(String v) apply,
    ) {
      final direct = d[scalarKey]?.toString().trim();
      if (direct != null && direct.isNotEmpty) {
        apply(direct);
        return;
      }
      final raw = d[optKey];
      if (raw is List && raw.isNotEmpty) {
        final s = raw.first.toString().trim();
        if (s.isNotEmpty) apply(s);
      }
    }

    setState(() {
      selectedMileage = d['mileage']?.toString();
      selectedCondition = d['condition']?.toString();
      takeScalarOrOnlineOpt(
        'transmission',
        '_online_opts_transmission',
        (v) => selectedTransmission = v,
      );
      takeScalarOrOnlineOpt(
        'fuel_type',
        '_online_opts_fuel',
        (v) => selectedFuelType = v,
      );
      takeScalarOrOnlineOpt(
        'body_type',
        '_online_opts_body',
        (v) => selectedBodyType = v,
      );
      takeScalarOrOnlineOpt(
        'drive_type',
        '_online_opts_drive',
        (v) => selectedDriveType = v,
      );
      take('region_specs', (v) {
        final c = v.trim().toLowerCase();
        if (isValidCarRegionSpecCode(c)) selectedRegionSpecs = c;
      });
      takeScalarOrOnlineOpt(
        'seating',
        '_online_opts_seating',
        (v) => selectedSeating = v,
      );
      selectedColor = d['color']?.toString();
      final rawTitle = d['title_status']?.toString().trim();
      if (rawTitle != null && rawTitle.isNotEmpty) {
        selectedTitleStatus = rawTitle;
      }
      selectedDamagedParts = d['damaged_parts']?.toString();
      final rawVin = d['vin']?.toString().trim();
      if (rawVin != null && rawVin.isNotEmpty) {
        selectedVin = rawVin;
        _vinController.text = rawVin;
      }
      takeScalarOrOnlineOpt(
        'cylinder_count',
        '_online_opts_cylinder',
        (v) => selectedCylinderCount = v,
      );
      String? es = d['engine_size']?.toString().trim();
      if (es == null || es.isEmpty) {
        final raw = d['_online_opts_engine_size'];
        if (raw is List && raw.isNotEmpty) {
          for (final c in raw) {
            final t = c.toString().trim();
            final lit = OnlineSpecVariant.parseLeadingEngineLiters(t);
            if (lit != null && lit > 0.001) {
              es = t;
              break;
            }
          }
        }
      }
      if (es != null && es.isNotEmpty) {
        final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
        if (lit == null || lit <= 0.001) {
          es = null;
        }
      }
      if (es != null && es.isNotEmpty) {
        // Prefer staying in picker mode by snapping to an available option
        // based on leading liters (preserves suffix labels like "T").
        final available = getAvailableEngineSizes()
            .where((e) => e != 'Any')
            .map((e) => e.trim())
            .toList();
        String? resolved = available.contains(es) ? es : null;
        final lit = OnlineSpecVariant.parseLeadingEngineLiters(es);
        if (resolved == null && lit != null) {
          for (final opt in available) {
            final oL = OnlineSpecVariant.parseLeadingEngineLiters(opt);
            if (oL != null && (oL - lit).abs() < 0.06) {
              resolved = opt;
              break;
            }
          }
        }

        if (resolved != null && resolved.isNotEmpty) {
          selectedEngineSize = resolved;
          isEngineSizeManualInput = false;
          _engineSizeController.text =
              (OnlineSpecVariant.parseLeadingEngineLiters(resolved)
                      ?.toStringAsFixed(1) ??
                  '');
        } else {
          // Unknown label; fall back to manual input.
          isEngineSizeManualInput = true;
          _engineSizeController.text =
              (OnlineSpecVariant.parseLeadingEngineLiters(es)
                      ?.toStringAsFixed(1) ??
                  es);
          selectedEngineSize = _engineSizeController.text.trim().isEmpty
              ? es
              : _engineSizeController.text.trim();
        }
      }
    });
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _mileageFocusNode.dispose();
    _engineSizeFocusNode.dispose();
    _mileageController.dispose();
    _engineSizeController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      if (!mounted) return;
      setState(() {
        selectedMileage = data['selectedMileage']?.toString();
        selectedCondition = data['selectedCondition']?.toString();
        selectedTransmission = data['selectedTransmission']?.toString();
        selectedFuelType = data['selectedFuelType']?.toString();
        selectedBodyType = data['selectedBodyType']?.toString();
        selectedColor = data['selectedColor']?.toString();
        selectedDriveType = data['selectedDriveType']?.toString();
        selectedRegionSpecs = data['selectedRegionSpecs']?.toString();
        selectedSeating = data['selectedSeating']?.toString();
        selectedEngineSize = data['selectedEngineSize']?.toString();
        selectedCylinderCount = data['selectedCylinderCount']?.toString();
        selectedTitleStatus = data['selectedTitleStatus']?.toString();
        selectedDamagedParts = data['selectedDamagedParts']?.toString();
        selectedVin = data['selectedVin']?.toString();
        _vinController.text = selectedVin ?? '';
        errMileage = data['errMileage'] == true;
        errCondition = data['errCondition'] == true;
        errTransmission = data['errTransmission'] == true;
        errFuelType = data['errFuelType'] == true;
        errBodyType = data['errBodyType'] == true;
        errColor = data['errColor'] == true;
        errDrive = data['errDrive'] == true;
        errRegionSpecs = data['errRegionSpecs'] == true;
        errSeating = data['errSeating'] == true;
        errEngineSize = data['errEngineSize'] == true;
        errCylinderCount = data['errCylinderCount'] == true;
        errTitle = data['errTitle'] == true;
        errDamagedParts = data['errDamagedParts'] == true;
        isMileageManualInput = data['isMileageManualInput'] == true;
        isEngineSizeManualInput = data['isEngineSizeManualInput'] == true;
        _mileageController.text = data['mileageControllerText']?.toString() ?? '';
        _engineSizeController.text =
            data['engineSizeControllerText']?.toString() ?? '';
      });
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      if (parentState != null) {
        parentState.carData['mileage'] = selectedMileage;
        parentState.carData['condition'] = selectedCondition;
        parentState.carData['transmission'] = selectedTransmission;
        parentState.carData['fuel_type'] = selectedFuelType;
        parentState.carData['body_type'] = selectedBodyType;
        parentState.carData['color'] = selectedColor;
        parentState.carData['drive_type'] = selectedDriveType;
        parentState.carData['region_specs'] =
            selectedRegionSpecs?.trim().toLowerCase();
        parentState.carData['seating'] = selectedSeating;
        parentState.carData['engine_size'] = selectedEngineSize;
        parentState.carData['cylinder_count'] = selectedCylinderCount;
        parentState.carData['title_status'] = selectedTitleStatus;
        parentState.carData['damaged_parts'] = selectedDamagedParts;
        parentState.carData['vin'] = selectedVin;
        parentState.setState(() {});
      }
      _hydrateFromParentCarData(force: true);
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _draftKey,
        json.encode(<String, dynamic>{
          'selectedMileage': selectedMileage,
          'selectedCondition': selectedCondition,
          'selectedTransmission': selectedTransmission,
          'selectedFuelType': selectedFuelType,
          'selectedBodyType': selectedBodyType,
          'selectedColor': selectedColor,
          'selectedDriveType': selectedDriveType,
          'selectedRegionSpecs': selectedRegionSpecs,
          'selectedSeating': selectedSeating,
          'selectedEngineSize': selectedEngineSize,
          'selectedCylinderCount': selectedCylinderCount,
          'selectedTitleStatus': selectedTitleStatus,
          'selectedDamagedParts': selectedDamagedParts,
          'selectedVin': selectedVin,
          'errMileage': errMileage,
          'errCondition': errCondition,
          'errTransmission': errTransmission,
          'errFuelType': errFuelType,
          'errBodyType': errBodyType,
          'errColor': errColor,
          'errDrive': errDrive,
          'errRegionSpecs': errRegionSpecs,
          'errSeating': errSeating,
          'errEngineSize': errEngineSize,
          'errCylinderCount': errCylinderCount,
          'errTitle': errTitle,
          'errDamagedParts': errDamagedParts,
          'isMileageManualInput': isMileageManualInput,
          'isEngineSizeManualInput': isEngineSizeManualInput,
          'mileageControllerText': _mileageController.text,
          'engineSizeControllerText': _engineSizeController.text,
        }),
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hydrateFromParentCarData();
  }

  void _resetStep2() {
    selectedMileage = null;
    selectedCondition = null;
    selectedTransmission = null;
    selectedFuelType = null;
    selectedBodyType = null;
    selectedColor = null;
    selectedDriveType = null;
    selectedRegionSpecs = null;
    selectedSeating = null;
    selectedEngineSize = null;
    selectedCylinderCount = null;
    selectedTitleStatus = null;
    selectedDamagedParts = null;
    selectedVin = null;
  }

  void _dismissKeyboard() {
    // Clear focus from mileage field
    _mileageFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  final List<String> conditions = ['New', 'Used'];
  final List<String> transmissions = ['Automatic', 'Manual'];
  final List<String> fuelTypes = [
    'Gasoline',
    'Diesel',
    'Electric',
    'Hybrid',
    'Plug-in Hybrid',
  ];
  final List<String> bodyTypes = [
    'Sedan',
    'SUV',
    'Hatchback',
    'Coupe',
    'Convertible',
    'Wagon',
    'Pickup',
    'Van',
    'Minivan',
  ];
  final List<String> colors = [
    'Black',
    'White',
    'Silver',
    'Gray',
    'Red',
    'Blue',
    'Green',
    'Brown',
    'Gold',
    'Other',
  ];
  final List<String> driveTypes = ['FWD', 'RWD', 'AWD', '4WD'];
  final List<String> seatings = ['2', '4', '5', '6', '7', '8'];
  // Same engine size options as More Filters (0.5 to 16.0 step 0.1)
  final List<String> engineSizes = [
    'Any',
    '0.5',
    '0.6',
    '0.7',
    '0.8',
    '0.9',
    '1.0',
    '1.1',
    '1.2',
    '1.3',
    '1.4',
    '1.5',
    '1.6',
    '1.7',
    '1.8',
    '1.9',
    '2.0',
    '2.1',
    '2.2',
    '2.3',
    '2.4',
    '2.5',
    '2.6',
    '2.7',
    '2.8',
    '2.9',
    '3.0',
    '3.1',
    '3.2',
    '3.3',
    '3.4',
    '3.5',
    '3.6',
    '3.7',
    '3.8',
    '3.9',
    '4.0',
    '4.1',
    '4.2',
    '4.3',
    '4.4',
    '4.5',
    '4.6',
    '4.7',
    '4.8',
    '4.9',
    '5.0',
    '5.1',
    '5.2',
    '5.3',
    '5.4',
    '5.5',
    '5.6',
    '5.7',
    '5.8',
    '5.9',
    '6.0',
    '6.1',
    '6.2',
    '6.3',
    '6.4',
    '6.5',
    '6.6',
    '6.7',
    '6.8',
    '6.9',
    '7.0',
    '7.1',
    '7.2',
    '7.3',
    '7.4',
    '7.5',
    '7.6',
    '7.7',
    '7.8',
    '7.9',
    '8.0',
    '8.1',
    '8.2',
    '8.3',
    '8.4',
    '8.5',
    '8.6',
    '8.7',
    '8.8',
    '8.9',
    '9.0',
    '9.1',
    '9.2',
    '9.3',
    '9.4',
    '9.5',
    '9.6',
    '9.7',
    '9.8',
    '9.9',
    '10.0',
    '10.1',
    '10.2',
    '10.3',
    '10.4',
    '10.5',
    '10.6',
    '10.7',
    '10.8',
    '10.9',
    '11.0',
    '11.1',
    '11.2',
    '11.3',
    '11.4',
    '11.5',
    '11.6',
    '11.7',
    '11.8',
    '11.9',
    '12.0',
    '12.1',
    '12.2',
    '12.3',
    '12.4',
    '12.5',
    '12.6',
    '12.7',
    '12.8',
    '12.9',
    '13.0',
    '13.1',
    '13.2',
    '13.3',
    '13.4',
    '13.5',
    '13.6',
    '13.7',
    '13.8',
    '13.9',
    '14.0',
    '14.1',
    '14.2',
    '14.3',
    '14.4',
    '14.5',
    '14.6',
    '14.7',
    '14.8',
    '14.9',
    '15.0',
    '15.1',
    '15.2',
    '15.3',
    '15.4',
    '15.5',
    '15.6',
    '15.7',
    '15.8',
    '15.9',
    '16.0',
  ];
  final List<String> cylinderCounts = ['3', '4', '5', '6', '8', '10', '12'];
  final List<String> titleStatuses = ['Clean', 'Damaged'];

  List<String>? _onlineMultiFromCarData(String key) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData[key];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return null;
  }

  // Helpers to mirror search page availability with simple defaults
  List<String> getAvailableBodyTypes() {
    final online = _onlineMultiFromCarData('_online_opts_body');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.bodyTypes.isEmpty) return bodyTypes;
    final f = bodyTypes.where((e) => o.bodyTypes.contains(e)).toList();
    return f.isEmpty ? bodyTypes : f;
  }

  List<String> getAvailableColors() {
    return colors;
  }

  // Availability helpers aligned with More Filters (simple pass-throughs here)
  List<String> getAvailableConditions() {
    return conditions;
  }

  List<String> getAvailableTransmissions() {
    final online = _onlineMultiFromCarData('_online_opts_transmission');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.transmissions.isEmpty) return transmissions;
    final f = transmissions.where((e) => o.transmissions.contains(e)).toList();
    return f.isEmpty ? transmissions : f;
  }

  List<String> getAvailableFuelTypes() {
    final online = _onlineMultiFromCarData('_online_opts_fuel');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.fuelTypes.isEmpty) return fuelTypes;
    final f = fuelTypes.where((e) => o.fuelTypes.contains(e)).toList();
    return f.isEmpty ? fuelTypes : f;
  }

  List<String> getAvailableDriveTypes() {
    final online = _onlineMultiFromCarData('_online_opts_drive');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.driveTypes.isEmpty) return driveTypes;
    final f = driveTypes.where((e) => o.driveTypes.contains(e)).toList();
    return f.isEmpty ? driveTypes : f;
  }

  List<String> getAvailableSeatings() {
    final online = _onlineMultiFromCarData('_online_opts_seating');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.seatings.isEmpty) return seatings;
    final f = seatings.where((e) => o.seatings.contains(e)).toList();
    return f.isEmpty ? seatings : f;
  }

  List<String> getAvailableEngineSizes() {
    final onlineRaw = _onlineMultiFromCarData('_online_opts_engine_size');
    if (onlineRaw != null) {
      final online = onlineRaw.map((e) => e.toString().trim()).where((s) {
        final x = OnlineSpecVariant.parseLeadingEngineLiters(s);
        return x != null && x > 0.001;
      }).toList();
      if (online.isEmpty) {
        // Bad API data (e.g. 0.0 L) — use full list like no-online.
      } else if (online.length == 1) {
        return online;
      } else {
        return <String>['Any', ...online];
      }
    }
    final o = _catalogSellOpts;
    if (o == null || o.engineSizes.isEmpty) return engineSizes;
    final f = engineSizes
        .where((e) => e == 'Any' || o.engineSizes.contains(e))
        .toList();
    final concrete = f.where((e) => e != 'Any').toList();
    if (concrete.length == 1) {
      return concrete;
    }
    if (f.length <= 1) {
      return engineSizes;
    }
    return f;
  }

  List<String> getAvailableCylinderCounts() {
    final online = _onlineMultiFromCarData('_online_opts_cylinder');
    if (online != null) return online;
    final o = _catalogSellOpts;
    if (o == null || o.cylinderCounts.isEmpty) return cylinderCounts;
    final f = cylinderCounts
        .where((e) => o.cylinderCounts.contains(e))
        .toList();
    return f.isEmpty ? cylinderCounts : f;
  }

  List<OnlineSpecVariant>? _onlineSpecVariantsFromParent() {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData[_kOnlineSpecVariantsKey];
    if (raw is! List || raw.isEmpty) return null;
    final out = <OnlineSpecVariant>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(OnlineSpecVariant.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out.isEmpty ? null : out;
  }

  String? _sellStep2TransmissionLabelToApi(String? label) {
    if (label == null) return null;
    return label.toLowerCase().contains('manual') ? 'manual' : 'automatic';
  }

  String? _sellStep2DriveLabelToApi(String? label) {
    if (label == null) return null;
    switch (label.toUpperCase()) {
      case 'RWD':
        return 'rwd';
      case 'AWD':
        return 'awd';
      case '4WD':
        return '4wd';
      case 'FWD':
      default:
        return 'fwd';
    }
  }

  String? _sellStep2BodyLabelToApi(String? label) {
    if (label == null) return null;
    const apis = ['sedan', 'suv', 'hatchback', 'coupe', 'pickup', 'van'];
    for (final a in apis) {
      if (sellFlowBodyLabel(a) == label) return a;
    }
    return null;
  }

  String? _sellStep2FuelApiForMatch(
    List<OnlineSpecVariant> vs,
    String? displayLabel,
  ) {
    if (displayLabel == null || displayLabel.isEmpty) return null;
    for (final v in vs) {
      final f = v.fuelType ?? v.engineType;
      if (f != null && sellFlowFuelLabel(f) == displayLabel) return f;
    }
    switch (displayLabel) {
      case 'Diesel':
        return 'diesel';
      case 'Electric':
        return 'electric';
      case 'Hybrid':
        return 'hybrid';
      case 'Plug-in Hybrid':
        return 'plug-in hybrid';
      default:
        return 'gasoline';
    }
  }

  int? _sellStep2CurrentSeatingInt() {
    final s = selectedSeating?.trim();
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  void _applyOnlineVariantToSellStep2(OnlineSpecVariant v) {
    if (v.engineSizeLiters != null && !isEngineSizeManualInput) {
      // Keep suffix (T/D/TD) for display; submit parses leading liters.
      selectedEngineSize =
          '${v.engineSizeLiters!.toStringAsFixed(1)}${v.displacementSuffix}';
    }
    if (v.cylinderCount != null) {
      selectedCylinderCount = '${v.cylinderCount}';
    }
    if (v.transmission != null) {
      selectedTransmission = sellFlowTransmissionLabel(v.transmission!);
    }
    if (v.drivetrain != null) {
      selectedDriveType = sellFlowDriveLabel(v.drivetrain!);
    }
    if (v.bodyType != null) {
      selectedBodyType = sellFlowBodyLabel(v.bodyType!);
    }
    final fuelApi = v.fuelType ?? v.engineType;
    if (fuelApi != null) {
      selectedFuelType = sellFlowFuelLabel(fuelApi);
    }
    if (v.seating != null) {
      selectedSeating =
          sellFlowNearestSeatingLabel(v.seating) ?? '${v.seating}';
    }
  }

  /// When [carData] has multiple catalog spec variants, align fields to one matching row.
  void _syncStep2ToOnlineVariant(Set<String> anchors) {
    final vs = _onlineSpecVariantsFromParent();
    if (vs == null) return;
    final eng = isEngineSizeManualInput
        ? null
        : OnlineSpecVariant.parseLeadingEngineLiters(selectedEngineSize ?? '');
    final m = OnlineSpecVariant.matchBestAnchored(
      vs,
      anchors,
      engineLiters: eng,
      cylinders: int.tryParse((selectedCylinderCount ?? '').trim()),
      transmission: _sellStep2TransmissionLabelToApi(selectedTransmission),
      drivetrain: _sellStep2DriveLabelToApi(selectedDriveType),
      bodyType: _sellStep2BodyLabelToApi(selectedBodyType),
      fuelType: _sellStep2FuelApiForMatch(vs, selectedFuelType),
      seating: _sellStep2CurrentSeatingInt(),
      currentTransmission: _sellStep2TransmissionLabelToApi(
        selectedTransmission,
      ),
      currentDrivetrain: _sellStep2DriveLabelToApi(selectedDriveType),
      currentSeating: _sellStep2CurrentSeatingInt(),
    );
    if (m != null) _applyOnlineVariantToSellStep2(m);
  }

  void _syncStep2DraftToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['mileage'] = selectedMileage;
    parentState.carData['condition'] = selectedCondition;
    parentState.carData['transmission'] = selectedTransmission;
    parentState.carData['fuel_type'] = selectedFuelType;
    parentState.carData['body_type'] = selectedBodyType;
    parentState.carData['color'] = selectedColor;
    parentState.carData['drive_type'] = selectedDriveType;
    parentState.carData['region_specs'] =
        selectedRegionSpecs?.trim().toLowerCase();
    parentState.carData['seating'] = selectedSeating;
    parentState.carData['engine_size'] = selectedEngineSize;
    parentState.carData['cylinder_count'] = selectedCylinderCount;
    parentState.carData['title_status'] = selectedTitleStatus;
    parentState.carData['damaged_parts'] = selectedDamagedParts;
    final vinText = _vinController.text.trim();
    selectedVin = vinText.isNotEmpty ? vinText : null;
    parentState.carData['vin'] = selectedVin;
    unawaited(parentState._saveSellDraftSnapshot());
  }

  Color _colorFromName(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'silver':
        return Colors.grey[300]!;
      case 'gray':
        return Colors.grey[600]!;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'brown':
        return Colors.brown;
      case 'beige':
        return const Color(0xFFF5F5DC);
      case 'gold':
        return const Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }

  Future<String?> _pickFromList(String title, List<String> options) async {
    return await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return Transform.translate(
          offset: Offset(0, (1 - curved.value) * 30),
          child: Opacity(
            opacity: curved.value,
            child: Dialog(
              backgroundColor: Colors.grey[900]?.withOpacity(0.98),
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
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final value = options[index];
                          final lowerTitle = title.toLowerCase();
                          String displayText = value;
                          final bool isNumeric = RegExp(
                            r'^[0-9]+(\.[0-9]+)?$',
                          ).hasMatch(value);
                          if (lowerTitle.contains('price')) {
                            displayText = _formatCurrencyGlobal(context, value);
                          } else if (lowerTitle.contains('mileage') &&
                              isNumeric) {
                            final localeTag = Localizations.localeOf(
                              context,
                            ).toLanguageTag();
                            final nf = _decimalFormatterGlobal(context);
                            displayText =
                                '${_localizeDigitsGlobal(context, nf.format(num.tryParse(value) ?? 0))} ${AppLocalizations.of(context)!.unit_km}';
                          } else if (lowerTitle.contains('year') && isNumeric) {
                            displayText = _localizeDigitsGlobal(context, value);
                          } else if (lowerTitle.contains('seating') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}';
                          } else if (lowerTitle.contains('cylinder') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}';
                          } else if (lowerTitle.contains('region') &&
                              isValidCarRegionSpecCode(value)) {
                            displayText =
                                carRegionSpecDisplayLabelLocalized(context, value);
                          } else if (lowerTitle.contains('engine') &&
                              isNumeric) {
                            displayText =
                                '${_localizeDigitsGlobal(context, value)} L';
                          } else if (value == 'Any') {
                            displayText = AppLocalizations.of(
                              context,
                            )!.anyOption;
                          } else {
                            final translated = _translateValueGlobal(
                              context,
                              value,
                            );
                            if (translated != null) displayText = translated;
                          }
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
                                    Colors.white.withOpacity(0.06),
                                    Colors.white.withOpacity(0.02),
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
                                      displayText,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                  ),
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
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.settings, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.carDetailsTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.carDetailsSubtitle,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Mileage (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isMileageManualInput
                      ? TextFormField(
                          focusNode: _mileageFocusNode,
                          controller: _mileageController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.mileageKmLabel} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.enterMileage,
                            filled: true,
                            fillColor: _sellFlowManualFieldFill(context),
                            labelStyle: _sellFlowManualFieldLabelStyle(context),
                            hintStyle: _sellFlowManualFieldHintStyle(context),
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
                          onChanged: (value) {
                            setState(() {
                              selectedMileage = value.isEmpty ? null : value;
                            });
                            _syncStep2DraftToParent();
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseEnterMileage;
                            }
                            final mileage = int.tryParse(value);
                            if (mileage == null) return l.invalidMileage;
                            if (mileage < 0) {
                              return l.mileageNegative;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) =>
                              (selectedMileage == null ||
                                  selectedMileage!.isEmpty)
                              ? AppLocalizations.of(
                                  context,
                                )!.pleaseSelectMileage
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final miles = [
                                ...[
                                  for (int m = 0; m <= 100000; m += 1000)
                                    m.toString(),
                                ],
                                ...[
                                  for (int m = 105000; m <= 300000; m += 5000)
                                    m.toString(),
                                ],
                              ];
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.mileageKmLabel,
                                miles,
                              );
                              if (choice != null) {
                                setState(() => selectedMileage = choice);
                                _syncStep2DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.speed,
                              label:
                                  '${AppLocalizations.of(context)!.mileageKmLabel} *',
                              value: selectedMileage != null
                                  ? ('${_localizeDigitsGlobal(context, _decimalFormatterGlobal(context).format(int.tryParse(selectedMileage!) ?? 0))} ${AppLocalizations.of(context)!.unit_km}')
                                  : null,
                              isError:
                                  errMileage &&
                                  (selectedMileage == null ||
                                      selectedMileage!.isEmpty),
                            ),
                          ),
                        ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isMileageManualInput) {
                      // If in manual input mode, confirm the mileage and dismiss keyboard
                      _mileageFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isMileageManualInput = false;
                        // Ensure the selectedMileage is properly set
                        if (_mileageController.text.isNotEmpty) {
                          selectedMileage = _mileageController.text;
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
                      // If in dropdown mode, switch to manual input
                      setState(() {
                        isMileageManualInput = true;
                        // Clear the controller to start fresh
                        _mileageController.clear();
                        selectedMileage = null;
                      });
                      _syncStep2DraftToParent();
                    }
                  },
                  icon: Icon(
                    isMileageManualInput ? Icons.check : Icons.edit,
                    color: Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isMileageManualInput
                      ? AppLocalizations.of(context)!.confirmMileage
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
            SizedBox(height: 16),

            // Condition (Modal)
            FormField<String>(
              validator: (_) => selectedCondition == null
                  ? AppLocalizations.of(context)!.pleaseSelectCondition
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.conditionLabel,
                    getAvailableConditions(),
                  );
                  if (choice != null) {
                    setState(() => selectedCondition = choice);
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.check_circle,
                  label: '${AppLocalizations.of(context)!.conditionLabel} *',
                  value: _translateValueGlobal(context, selectedCondition),
                  isError:
                      errCondition &&
                      (selectedCondition == null || selectedCondition!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Transmission (Modal)
            FormField<String>(
              validator: (_) => selectedTransmission == null
                  ? AppLocalizations.of(context)!.pleaseSelectTransmission
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.transmissionLabel,
                    getAvailableTransmissions(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTransmission = choice;
                      _syncStep2ToOnlineVariant({'tr'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings,
                  label: '${AppLocalizations.of(context)!.transmissionLabel} *',
                  value: _translateValueGlobal(context, selectedTransmission),
                  isError:
                      errTransmission &&
                      (selectedTransmission == null ||
                          selectedTransmission!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Fuel Type (Modal)
            FormField<String>(
              validator: (_) => selectedFuelType == null
                  ? AppLocalizations.of(context)!.pleaseSelectFuelType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.fuelTypeLabel,
                    getAvailableFuelTypes(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedFuelType = choice;
                      _syncStep2ToOnlineVariant({'fuel'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.local_gas_station,
                  label: '${AppLocalizations.of(context)!.fuelTypeLabel} *',
                  value: _translateValueGlobal(context, selectedFuelType),
                  isError:
                      errFuelType &&
                      (selectedFuelType == null || selectedFuelType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Body Type (Modal - grid like search)
            FormField<String>(
              validator: (_) => selectedBodyType == null
                  ? AppLocalizations.of(context)!.pleaseSelectBodyType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.selectBodyType,
                                    style: GoogleFonts.orbitron(
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 0.82,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                  itemCount: getAvailableBodyTypes().length,
                                  itemBuilder: (context, index) {
                                    final bodyTypeName =
                                        getAvailableBodyTypes()[index];
                                    final asset = _getBodyTypeAsset(
                                      bodyTypeName,
                                    );
                                    final bool isSelected =
                                        (selectedBodyType ?? '') ==
                                        bodyTypeName;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, bodyTypeName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFFFF6B00)
                                                : Colors.white24,
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFFFF6B00,
                                                    ).withOpacity(0.35),
                                                    blurRadius: 14,
                                                    spreadRadius: 1,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : [
                                                  const BoxShadow(
                                                    color: Colors.black54,
                                                    blurRadius: 10,
                                                    spreadRadius: 0,
                                                    offset: Offset(0, 3),
                                                  ),
                                                ],
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? const Color(0xFFFF6B00)
                                                      : Colors.white24,
                                                  width: isSelected ? 2 : 1,
                                                ),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: _buildBodyTypeImage(
                                                    asset,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              bodyTypeName == 'Any'
                                                  ? AppLocalizations.of(
                                                      context,
                                                    )!.anyOption
                                                  : (_translateValueGlobal(
                                                          context,
                                                          bodyTypeName,
                                                        ) ??
                                                        bodyTypeName),
                                              style: GoogleFonts.orbitron(
                                                fontSize: 12,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white70,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
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
                  if (choice != null) {
                    setState(() {
                      selectedBodyType = choice;
                      _syncStep2ToOnlineVariant({'body'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions_car,
                  label: '${AppLocalizations.of(context)!.bodyTypeLabel} *',
                  value: selectedBodyType == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedBodyType) ??
                          selectedBodyType),
                  isError:
                      errBodyType &&
                      (selectedBodyType == null || selectedBodyType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Color (Modal - swatches like search)
            FormField<String>(
              validator: (_) => selectedColor == null
                  ? AppLocalizations.of(context)!.pleaseSelectColor
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        backgroundColor: Colors.grey[900]?.withOpacity(0.98),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: 400,
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)!.selectColor,
                                    style: GoogleFonts.orbitron(
                                      color: Color(0xFFFF6B00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              SizedBox(
                                height: 300,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 1.2,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                  itemCount: getAvailableColors().length,
                                  itemBuilder: (context, index) {
                                    final colorName =
                                        getAvailableColors()[index];
                                    final colorValue = _colorFromName(
                                      colorName,
                                    );
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () =>
                                          Navigator.pop(context, colorName),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white24,
                                          ),
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: colorValue,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white24,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              _translateValueGlobal(
                                                    context,
                                                    colorName,
                                                  ) ??
                                                  colorName,
                                              style: GoogleFonts.orbitron(
                                                fontSize: 12,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
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
                  if (choice != null) setState(() => selectedColor = choice);
                  if (choice != null) _syncStep2DraftToParent();
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.palette,
                  label: '${AppLocalizations.of(context)!.colorLabel} *',
                  value: selectedColor == null
                      ? _tapToSelectTextGlobal(context)
                      : (_translateValueGlobal(context, selectedColor) ??
                          selectedColor),
                  isError:
                      errColor &&
                      (selectedColor == null || selectedColor!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Drive Type (Modal)
            FormField<String>(
              validator: (_) => selectedDriveType == null
                  ? AppLocalizations.of(context)!.pleaseSelectDriveType
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.driveType,
                    getAvailableDriveTypes(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedDriveType = choice;
                      _syncStep2ToOnlineVariant({'drv'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.directions,
                  label: '${AppLocalizations.of(context)!.driveType} *',
                  value: _translateValueGlobal(context, selectedDriveType),
                  isError:
                      errDrive &&
                      (selectedDriveType == null || selectedDriveType!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            FormField<String>(
              validator: (_) =>
                  (selectedRegionSpecs == null ||
                      !isValidCarRegionSpecCode(selectedRegionSpecs))
                  ? AppLocalizations.of(context)!.pleaseSelectRegionSpecs
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.regionSpecsLabel,
                    List<String>.from(kCarRegionSpecCodes),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedRegionSpecs = choice.trim().toLowerCase();
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.public,
                  label: '${AppLocalizations.of(context)!.regionSpecsLabel} *',
                  value: selectedRegionSpecs == null
                      ? null
                      : carRegionSpecDisplayLabelLocalized(
                          context,
                          selectedRegionSpecs!,
                        ),
                  isError:
                      errRegionSpecs &&
                      (selectedRegionSpecs == null ||
                          !isValidCarRegionSpecCode(selectedRegionSpecs)),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Seating (Modal)
            FormField<String>(
              validator: (_) => selectedSeating == null
                  ? AppLocalizations.of(context)!.pleaseSelectSeating
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.seating,
                    getAvailableSeatings().where((s) => s != 'Any').toList(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedSeating = choice;
                      _syncStep2ToOnlineVariant({'seat'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.people,
                  label: '${AppLocalizations.of(context)!.seating} *',
                  value: selectedSeating == null
                      ? null
                      : ('${_localizeDigitsGlobal(context, selectedSeating!)} ${_trLegacyText(context, 'seats', ar: 'مقاعد', ku: 'دانیشتن')}'),
                  isError:
                      errSeating &&
                      (selectedSeating == null || selectedSeating!.isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Engine Size (Modal or Manual Input)
            Row(
              children: [
                Expanded(
                  child: isEngineSizeManualInput
                      ? TextFormField(
                          focusNode: _engineSizeFocusNode,
                          controller: _engineSizeController,
                          decoration: InputDecoration(
                            labelText:
                                '${AppLocalizations.of(context)!.engineSizeL} *',
                            hintText: AppLocalizations.of(
                              context,
                            )!.pleaseSelectEngineSize,
                            filled: true,
                            fillColor: _sellFlowManualFieldFill(context),
                            labelStyle: _sellFlowManualFieldLabelStyle(context),
                            hintStyle: _sellFlowManualFieldHintStyle(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.red),
                            ),
                            errorText: () {
                              if (!errEngineSize) return null;
                              final raw = _engineSizeController.text.trim();
                              final l = AppLocalizations.of(context)!;
                              if (raw.isEmpty) return l.pleaseSelectEngineSize;
                              final size = double.tryParse(raw);
                              if (size == null || size <= 0) {
                                return l.pleaseSelectEngineSize;
                              }
                              return null;
                            }(),
                          ),
                          style: _sellFlowManualFieldTextStyle(context),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            services.FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedEngineSize = value.isEmpty
                                  ? null
                                  : value.trim();
                              if (errEngineSize) errEngineSize = false;
                            });
                            _syncStep2DraftToParent();
                          },
                          validator: (value) {
                            final l = AppLocalizations.of(context)!;
                            if (value == null || value.isEmpty) {
                              return l.pleaseSelectEngineSize;
                            }
                            final size = double.tryParse(value);
                            if (size == null) return l.pleaseSelectEngineSize;
                            if (size <= 0) {
                              return l.pleaseSelectEngineSize;
                            }
                            return null;
                          },
                        )
                      : FormField<String>(
                          validator: (_) =>
                              (selectedEngineSize == null ||
                                  selectedEngineSize!.isEmpty)
                              ? AppLocalizations.of(
                                  context,
                                )!.pleaseSelectEngineSize
                              : null,
                          builder: (state) => GestureDetector(
                            onTap: () async {
                              final choice = await _pickFromList(
                                AppLocalizations.of(context)!.engineSizeL,
                                getAvailableEngineSizes()
                                    .where((e) => e != 'Any')
                                    .toList(),
                              );
                              if (choice != null) {
                                setState(() {
                                  selectedEngineSize = choice.replaceAll(
                                    ' L',
                                    '',
                                  );
                                  if (errEngineSize) errEngineSize = false;
                                  _syncStep2ToOnlineVariant({'e'});
                                });
                                _syncStep2DraftToParent();
                              }
                            },
                            child: buildFancySelector(
                              context,
                              icon: Icons.engineering,
                              label:
                                  '${AppLocalizations.of(context)!.engineSizeL} *',
                              value: selectedEngineSize == null
                                  ? null
                                  : _engineSizeSellRowLabel(
                                      context,
                                      selectedEngineSize!,
                                    ),
                              isError:
                                  errEngineSize &&
                                  (selectedEngineSize == null ||
                                      selectedEngineSize!.trim().isEmpty),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isEngineSizeManualInput) {
                      // Confirm manual engine size and dismiss keyboard
                      _engineSizeFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isEngineSizeManualInput = false;
                        if (_engineSizeController.text.isNotEmpty) {
                          selectedEngineSize = _engineSizeController.text
                              .trim();
                          _syncStep2ToOnlineVariant({'e'});
                        }
                      });
                      _syncStep2DraftToParent();
                    } else {
                      // Switch from modal picker to manual input
                      setState(() {
                        isEngineSizeManualInput = true;
                        _engineSizeController.clear();
                        selectedEngineSize = null;
                      });
                      _syncStep2DraftToParent();
                    }
                  },
                  icon: Icon(
                    isEngineSizeManualInput ? Icons.check : Icons.edit,
                    color: const Color(0xFFFF6B00),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isEngineSizeManualInput
                      ? AppLocalizations.of(context)!.confirmYear
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cylinder Count (Modal)
            FormField<String>(
              validator: (_) =>
                  (selectedCylinderCount == null ||
                      selectedCylinderCount!.trim().isEmpty)
                  ? AppLocalizations.of(context)!.pleaseSelectCylinderCount
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.cylinderCount,
                    getAvailableCylinderCounts()
                        .where((c) => c != 'Any')
                        .toList(),
                  );
                  if (choice != null) {
                    setState(() {
                      selectedCylinderCount = choice.replaceAll(
                        ' cylinders',
                        '',
                      );
                      if (errCylinderCount) errCylinderCount = false;
                      _syncStep2ToOnlineVariant({'c'});
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.settings_input_component,
                  label: '${AppLocalizations.of(context)!.cylinderCount} *',
                  value: selectedCylinderCount == null
                      ? null
                      : ('${_localizeDigitsGlobal(context, selectedCylinderCount!)} ${_trLegacyText(context, 'cylinders', ar: 'أسطوانات', ku: 'سیلەندەر')}'),
                  isError:
                      errCylinderCount &&
                      (selectedCylinderCount == null ||
                          selectedCylinderCount!.trim().isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Title Status (Modal)
            FormField<String>(
              validator: (_) => selectedTitleStatus == null
                  ? AppLocalizations.of(context)!.titleStatus
                  : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.titleStatus,
                    titleStatuses,
                  );
                  if (choice != null) {
                    setState(() {
                      selectedTitleStatus = choice;
                      if (choice != 'Damaged') selectedDamagedParts = null;
                    });
                    _syncStep2DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.description,
                  label: '${AppLocalizations.of(context)!.titleStatus} *',
                  value: _translateValueGlobal(context, selectedTitleStatus),
                  isError:
                      errTitle &&
                      (selectedTitleStatus == null ||
                          (selectedTitleStatus ?? '').isEmpty),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Damaged Parts modal
            if ((selectedTitleStatus ?? '').toLowerCase() == 'damaged')
              FormField<String>(
                builder: (state) => GestureDetector(
                  onTap: () async {
                    final nums = List.generate(20, (i) => (i + 1).toString());
                    final choice = await _pickFromList(
                      AppLocalizations.of(context)!.damagedParts,
                      nums,
                    );
                    if (choice != null) {
                      setState(() => selectedDamagedParts = choice);
                    _syncStep2DraftToParent();
                    }
                  },
                  child: buildFancySelector(
                    context,
                    icon: Icons.warning,
                    label: AppLocalizations.of(context)!.damagedParts,
                    value: selectedDamagedParts == null
                        ? null
                        : _localizeDigitsGlobal(context, selectedDamagedParts!),
                    isError:
                        errDamagedParts &&
                        (selectedDamagedParts == null ||
                            selectedDamagedParts!.isEmpty),
                  ),
                ),
              ),
            SizedBox(height: 16),

            // VIN (optional)
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.3)),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: _vinController,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  icon: Icon(Icons.pin_outlined, color: Color(0xFFFF6B00)),
                  labelText: _trLegacyText(
                    context,
                    'VIN (optional)',
                    ar: 'رقم الهيكل (اختياري)',
                    ku: 'ژمارەی شاسی (ئارەزوومەندانە)',
                  ),
                  labelStyle: TextStyle(color: Colors.white70),
                  hintText: 'e.g. 1HGBH41JXMN109186',
                  hintStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (value) {
                  selectedVin = value.trim().isEmpty ? null : value.trim();
                  _syncStep2DraftToParent();
                },
                validator: (v) {
                  final trimmed = (v ?? '').trim();
                  if (trimmed.isEmpty) return null;
                  if (trimmed.length != 17) {
                    return _trLegacyText(
                      context,
                      'VIN must be 17 characters',
                      ar: 'رقم الهيكل يجب أن يكون 17 حرفاً',
                      ku: 'ژمارەی شاسی دەبێت ١٧ پیت بێت',
                    );
                  }
                  return null;
                },
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
                        if (selectedMileage == null ||
                            (selectedMileage ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.mileageLabel,
                          );
                        }
                        if (selectedCondition == null ||
                            (selectedCondition ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.conditionLabel,
                          );
                        }
                        if (selectedTransmission == null ||
                            (selectedTransmission ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.transmissionLabel,
                          );
                        }
                        if (selectedFuelType == null ||
                            (selectedFuelType ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.fuelTypeLabel,
                          );
                        }
                        if (selectedBodyType == null ||
                            (selectedBodyType ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.selectBodyType,
                          );
                        }
                        if (selectedColor == null ||
                            (selectedColor ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.selectColor,
                          );
                        }
                        if (selectedDriveType == null ||
                            (selectedDriveType ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.driveType);
                        }
                        if (selectedRegionSpecs == null ||
                            !isValidCarRegionSpecCode(selectedRegionSpecs)) {
                          missing.add(
                            AppLocalizations.of(context)!.regionSpecsLabel,
                          );
                        }
                        if (selectedSeating == null ||
                            (selectedSeating ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.seating);
                        }
                        final String engineForStep = isEngineSizeManualInput
                            ? _engineSizeController.text.trim()
                            : (selectedEngineSize ?? '').trim();
                        final double? engineLiters =
                            OnlineSpecVariant.parseLeadingEngineLiters(
                                  engineForStep,
                                ) ??
                                double.tryParse(engineForStep);
                        final bool engineOk =
                            engineForStep.isNotEmpty &&
                            engineLiters != null &&
                            engineLiters > 0;
                        if (!engineOk) {
                          missing.add(
                            AppLocalizations.of(context)!.engineSizeL,
                          );
                        }
                        if (selectedCylinderCount == null ||
                            selectedCylinderCount!.trim().isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.cylinderCount,
                          );
                        }
                        if (selectedTitleStatus == null ||
                            (selectedTitleStatus ?? '').isEmpty) {
                          missing.add(
                            AppLocalizations.of(context)!.titleStatus,
                          );
                        }
                        if ((selectedTitleStatus?.toLowerCase() == 'damaged') &&
                            (selectedDamagedParts == null ||
                                (selectedDamagedParts ?? '').isEmpty)) {
                          missing.add(
                            AppLocalizations.of(context)!.damagedParts,
                          );
                        }
                        if (missing.isNotEmpty) {
                          setState(() {
                            errMileage =
                                selectedMileage == null ||
                                (selectedMileage ?? '').isEmpty;
                            errCondition =
                                selectedCondition == null ||
                                (selectedCondition ?? '').isEmpty;
                            errTransmission =
                                selectedTransmission == null ||
                                (selectedTransmission ?? '').isEmpty;
                            errFuelType =
                                selectedFuelType == null ||
                                (selectedFuelType ?? '').isEmpty;
                            errBodyType =
                                selectedBodyType == null ||
                                (selectedBodyType ?? '').isEmpty;
                            errColor =
                                selectedColor == null ||
                                (selectedColor ?? '').isEmpty;
                            errDrive =
                                selectedDriveType == null ||
                                (selectedDriveType ?? '').isEmpty;
                            errRegionSpecs =
                                selectedRegionSpecs == null ||
                                !isValidCarRegionSpecCode(selectedRegionSpecs);
                            errSeating =
                                selectedSeating == null ||
                                (selectedSeating ?? '').isEmpty;
                            errEngineSize = !engineOk;
                            errCylinderCount =
                                selectedCylinderCount == null ||
                                selectedCylinderCount!.trim().isEmpty;
                            errTitle =
                                selectedTitleStatus == null ||
                                (selectedTitleStatus ?? '').isEmpty;
                            errDamagedParts =
                                (selectedTitleStatus?.toLowerCase() ==
                                    'damaged') &&
                                (selectedDamagedParts == null ||
                                    (selectedDamagedParts ?? '').isEmpty);
                          });
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
                          if (isEngineSizeManualInput) {
                            final te = _engineSizeController.text.trim();
                            if (te.isNotEmpty) selectedEngineSize = te;
                          }
                          parentState.carData['mileage'] = selectedMileage;
                          parentState.carData['condition'] = selectedCondition;
                          parentState.carData['transmission'] =
                              selectedTransmission;
                          parentState.carData['fuel_type'] = selectedFuelType;
                          parentState.carData['body_type'] = selectedBodyType;
                          parentState.carData['color'] = selectedColor;
                          parentState.carData['drive_type'] = selectedDriveType;
                          parentState.carData['region_specs'] =
                              selectedRegionSpecs?.trim().toLowerCase();
                          parentState.carData['seating'] = selectedSeating;
                          parentState.carData['engine_size'] =
                              selectedEngineSize;
                          parentState.carData['cylinder_count'] =
                              selectedCylinderCount;
                          parentState.carData['title_status'] =
                              selectedTitleStatus;
                          parentState.carData['damaged_parts'] =
                              selectedDamagedParts;
                          final vinText = _vinController.text.trim();
                          parentState.carData['vin'] =
                              vinText.isNotEmpty ? vinText : null;
                          setState(() {
                            errMileage = errCondition = errTransmission =
                                errFuelType = errBodyType = errColor =
                                    errDrive = errRegionSpecs = errSeating =
                                        errEngineSize = errCylinderCount =
                                            errTitle = errDamagedParts = false;
                          });
                          parentState._goToNextStep();
                          unawaited(parentState._saveSellDraftSnapshot());
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
    );
  }
}

// Step 3: Pricing & Contact Information
class SellStep3Page extends StatefulWidget {
  const SellStep3Page({super.key});

  @override
  _SellStep3PageState createState() => _SellStep3PageState();
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

  Future<void> _restoreDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      if (!mounted) return;
      setState(() {
        selectedPrice = data['selectedPrice']?.toString();
        selectedCity = data['selectedCity']?.toString();
        selectedPlateType = data['selectedPlateType']?.toString();
        selectedPlateCity = data['selectedPlateCity']?.toString();
        contactPhone = data['contactPhone']?.toString();
        isQuickSell = data['isQuickSell'] == true;
        isPriceManualInput = data['isPriceManualInput'] == true;
        selectedCurrency = data['selectedCurrency']?.toString() ?? 'USD';
        _priceController.text = data['priceControllerText']?.toString() ?? '';
        _phoneController.text =
            (contactPhone ?? '').replaceFirst(RegExp(r'^\+964'), '');
        _descriptionController.text =
            data['descriptionControllerText']?.toString() ?? '';
      });
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      if (parentState != null) {
        parentState.carData['price'] = selectedPrice;
        parentState.carData['city'] = selectedCity;
        parentState.carData['plate_type'] = selectedPlateType;
        parentState.carData['plate_city'] = selectedPlateCity;
        parentState.carData['contact_phone'] = contactPhone;
        parentState.carData['quick_sell'] = isQuickSell;
        parentState.carData['currency'] = selectedCurrency;
        parentState.carData['description'] = _descriptionController.text;
        parentState.setState(() {});
      }
    } catch (_) {}
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
    } catch (_) {}
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
    // Clear focus from all number input fields
    _priceFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  Widget _buildCurrencyButton(String currency, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCurrency = currency;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFFF6B00) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          currency,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
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
          backgroundColor: Colors.grey[900]?.withOpacity(0.98),
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
                    separatorBuilder: (_, __) => SizedBox(height: 10),
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
                                Colors.white.withOpacity(0.06),
                                Colors.white.withOpacity(0.02),
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
    return SingleChildScrollView(
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
                  colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
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
                        backgroundColor: Colors.grey.withOpacity(0.1),
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
                        backgroundColor: Colors.grey.withOpacity(0.1),
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
              onTap: () => _dismissKeyboard(),
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
              onTap: () => _dismissKeyboard(),
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
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
    );
  }
}

// Step 4: Photos & Videos
class SellStep4Page extends StatefulWidget {
  const SellStep4Page({super.key});

  @override
  _SellStep4PageState createState() => _SellStep4PageState();
}

class _SellStep4PageState extends State<SellStep4Page> {
  static const String _draftKey = 'legacy_sell_draft_step4_v1';
  final ImagePicker _imagePicker = ImagePicker();
  // Can contain either local XFile (original picks) or server-relative paths (after "Blur Plates").
  List<dynamic> _selectedImages = [];
  /// Local picks and/or server-relative paths for damage / crash disclosure.
  List<dynamic> _damageImages = [];
  final List<XFile> _selectedVideos = [];
  bool _videosHydratedFromParent = false;
  bool _isProcessingImages = false;
  bool _imagesProcessed = false;

  dynamic _normalizeDraftImageItem(dynamic item) {
    if (item is XFile) return item;
    final raw = item?.toString().trim() ?? '';
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    final localPath = raw.startsWith('file://') ? raw.replaceFirst('file://', '') : raw;
    return File(localPath).existsSync() ? XFile(localPath) : raw;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMediaDraft());
  }

  Future<void> _loadMediaDraft() async {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final startFresh = parentState?.widget.startFreshListing == true;
    if (startFresh) {
      if (mounted) {
        setState(() {
          _selectedImages = [];
          _damageImages = [];
          _selectedVideos.clear();
          _imagesProcessed = false;
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData.remove('images');
        parentState.carData.remove('damage_images');
        parentState.carData.remove('videos');
        parentState.carData.remove('images_processed');
        parentState.carData.remove('processed_image_paths');
      }
    } else {
      final parentImages = parentState?.carData['images'];
      final parentDamage = parentState?.carData['damage_images'];
      final parentVideos = parentState?.carData['videos'];
      List<dynamic> stepImages = const [];
      List<dynamic> stepDamage = const [];
      List<XFile> stepVideos = const [];
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString(_draftKey);
        if (raw != null && raw.trim().isNotEmpty) {
          final decoded = json.decode(raw);
          if (decoded is Map) {
            final data = Map<String, dynamic>.from(
              decoded.cast<String, dynamic>(),
            );
            if (data['selectedImages'] is List) {
              stepImages = List<dynamic>.from(data['selectedImages'] as List);
            }
            if (data['damage_images'] is List) {
              stepDamage = List<dynamic>.from(data['damage_images'] as List);
            }
            if (data['selectedVideos'] is List) {
              stepVideos = (data['selectedVideos'] as List)
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty && File(e).existsSync())
                  .map((e) => XFile(e))
                  .toList();
            }
            _imagesProcessed = data['imagesProcessed'] == true;
          }
        }
      } catch (_) {}

      final mergedImages = SellDraftMediaPersistence.mergeRawMediaLists([
        if (parentImages is List) List<dynamic>.from(parentImages) else [],
        stepImages,
      ]);
      final mergedDamage = SellDraftMediaPersistence.mergeRawMediaLists([
        if (parentDamage is List) List<dynamic>.from(parentDamage) else [],
        stepDamage,
      ]);
      final mergedVideoPaths = <String>{
        if (parentVideos is List)
          ...parentVideos.map(
            (e) => e is XFile ? e.path : e.toString().trim(),
          ),
        ...stepVideos.map((e) => e.path),
      }.where((path) => path.isNotEmpty && File(path).existsSync());

      if (mounted) {
        setState(() {
          _selectedImages = mergedImages;
          _damageImages = mergedDamage;
          _selectedVideos
            ..clear()
            ..addAll(mergedVideoPaths.map((path) => XFile(path)));
          _isProcessingImages = false;
        });
      }
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(mergedImages);
        parentState.carData['damage_images'] =
            List<dynamic>.from(mergedDamage);
        parentState.carData['videos'] = List<XFile>.from(
          mergedVideoPaths.map((path) => XFile(path)),
        );
        parentState.carData['images_processed'] = _imagesProcessed;
      }
    }
    if (!mounted) return;
    if (_selectedImages.isNotEmpty ||
        _damageImages.isNotEmpty ||
        _selectedVideos.isNotEmpty) {
      await _syncMediaDraftToParent();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videosHydratedFromParent) return;
    _videosHydratedFromParent = true;
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final dynamic saved = parentState?.carData['videos'];
    if (saved is List && saved.isNotEmpty) {
      for (final dynamic item in saved) {
        if (item is XFile) {
          _selectedVideos.add(item);
        } else if (item is String && item.trim().isNotEmpty) {
          _selectedVideos.add(XFile(item.trim()));
        }
      }
    }
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(_selectedImages);
        parentState.carData['damage_images'] =
            List<dynamic>.from(_damageImages);
        parentState.carData['videos'] = List<XFile>.from(_selectedVideos);
        parentState.carData['images_processed'] = _imagesProcessed;
      }
      unawaited(
        _saveDraft().then((_) {
          parentState?._saveSellDraftSnapshot();
        }),
      );
    }
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      final images = data['selectedImages'];
      final videos = data['selectedVideos'];
      final dmg = data['damage_images'];
      if (!mounted) return;
      setState(() {
        _selectedImages = images is List
            ? SellDraftMediaPersistence.resolveDynamicMediaList(
                List<dynamic>.from(images),
              )
            : _selectedImages;
        _damageImages = dmg is List
            ? SellDraftMediaPersistence.resolveDynamicMediaList(
                List<dynamic>.from(dmg),
              )
            : <dynamic>[];
        _selectedVideos
          ..clear()
          ..addAll(
            videos is List
                ? videos
                    .map((e) => e.toString())
                    .where((e) => e.trim().isNotEmpty && File(e).existsSync())
                    .map((e) => XFile(e))
                    .toList()
                : <XFile>[],
          );
        _imagesProcessed = data['imagesProcessed'] == true;
        _isProcessingImages = false;
      });
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(_selectedImages);
        parentState.carData['videos'] = List<XFile>.from(_selectedVideos);
        parentState.carData['damage_images'] =
            List<dynamic>.from(_damageImages);
        parentState.setState(() {});
      }
    } catch (_) {}
  }

  void _hydrateFromParentCarData() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final videos = parentState?.carData['videos'];
    final images = parentState?.carData['images'];
    final dmg = parentState?.carData['damage_images'];
    final hasDamageList = dmg is List && dmg.isNotEmpty;
    if ((images is! List || images.isEmpty) &&
        (videos is! List || videos.isEmpty) &&
        !hasDamageList) {
      return;
    }
    setState(() {
      _selectedImages = images is List
          ? SellDraftMediaPersistence.resolveDynamicMediaList(
              List<dynamic>.from(images),
            )
          : _selectedImages;
      _damageImages = hasDamageList
          ? SellDraftMediaPersistence.resolveDynamicMediaList(
              List<dynamic>.from(dmg as List),
            )
          : <dynamic>[];
      _selectedVideos.clear();
      if (videos is List) {
        for (final dynamic item in videos) {
          if (item is XFile) {
            _selectedVideos.add(item);
          } else if (item is String && item.trim().isNotEmpty) {
            _selectedVideos.add(XFile(item.trim()));
          }
        }
      }
      _videosHydratedFromParent = true;
      _imagesProcessed = parentState?.carData['images_processed'] == true || _imagesProcessed;
      _isProcessingImages = false;
    });
  }

  Future<void> _saveDraft() async {
    try {
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';
      final images = await SellDraftMediaPersistence.persistDynamicMediaList(
        _selectedImages,
        draftId: draftId,
        namePrefix: 'listing',
      );
      final damage = await SellDraftMediaPersistence.persistDynamicMediaList(
        _damageImages,
        draftId: draftId,
        namePrefix: 'damage',
      );
      final videos = await SellDraftMediaPersistence.persistDynamicMediaList(
        _selectedVideos,
        draftId: draftId,
        namePrefix: 'video',
      );
      if (mounted) {
        setState(() {
          _selectedImages = images;
          _damageImages = damage;
          _selectedVideos
            ..clear()
            ..addAll(videos.whereType<XFile>());
        });
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _draftKey,
        json.encode(<String, dynamic>{
          'selectedImages': images
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'damage_images': damage
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'selectedVideos': videos
              .map((e) => e is XFile ? e.path : e.toString())
              .toList(),
          'imagesProcessed': _imagesProcessed,
        }),
      );
      if (parentState != null) {
        parentState.carData['images'] = List<dynamic>.from(images);
        parentState.carData['damage_images'] = List<dynamic>.from(damage);
        parentState.carData['videos'] = List<XFile>.from(
          videos.whereType<XFile>(),
        );
        parentState.carData['images_processed'] = _imagesProcessed;
      }
      unawaited(parentState?._saveSellDraftSnapshot());
    } catch (_) {}
  }

  void _syncVideosToParent() {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    parentState.carData['videos'] = List<XFile>.from(_selectedVideos);
  }

  Future<void> _syncMediaDraftToParent() async {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    if (parentState == null) return;
    final draftId = parentState._currentDraftId;
    final images = await SellDraftMediaPersistence.persistDynamicMediaList(
      _selectedImages,
      draftId: draftId,
      namePrefix: 'listing',
    );
    final damage = await SellDraftMediaPersistence.persistDynamicMediaList(
      _damageImages,
      draftId: draftId,
      namePrefix: 'damage',
    );
    final videos = await SellDraftMediaPersistence.persistDynamicMediaList(
      _selectedVideos,
      draftId: draftId,
      namePrefix: 'video',
    );
    if (!mounted) return;
    setState(() {
      _selectedImages = images;
      _damageImages = damage;
      _selectedVideos
        ..clear()
        ..addAll(videos.whereType<XFile>());
    });
    parentState.carData['images'] = List<dynamic>.from(images);
    parentState.carData['damage_images'] = List<dynamic>.from(damage);
    parentState.carData['videos'] = List<XFile>.from(
      videos.whereType<XFile>(),
    );
    parentState.carData['images_processed'] = _imagesProcessed;
    if (_imagesProcessed) {
      parentState.carData['processed_image_paths'] = images
          .map((e) => e is XFile ? e.path : e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } else {
      parentState.carData.remove('processed_image_paths');
    }
    parentState.setState(() {});
    unawaited(parentState._saveSellDraftSnapshot());
  }

  String _imagePathKey(dynamic item) =>
      item is XFile ? item.path : item.toString().trim();

  Future<void> _pickImages() async {
    try {
      // Upload full-resolution images to improve YOLO/OCR accuracy
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      final existing = _selectedImages.map(_imagePathKey).toSet();
      final additions = files.where((f) => !existing.contains(f.path)).toList();
      if (additions.isEmpty) return;
      setState(() {
        _selectedImages = [..._selectedImages, ...additions];
        _imagesProcessed = false;
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (_) {}
  }

  Future<void> _pickDamageImages() async {
    try {
      final files = await _imagePicker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      final existing = _damageImages.map(_imagePathKey).toSet();
      final additions = files.where((f) => !existing.contains(f.path)).toList();
      if (additions.isEmpty) return;
      setState(() {
        _damageImages = [..._damageImages, ...additions];
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (_) {}
  }

  Future<void> _processImages() async {
    if (_selectedImages.isEmpty) {
      _debugLog('AI UI: No images selected for processing');
      return;
    }

    _debugLog(
      'AI UI: Starting image processing for ${_selectedImages.length} images',
    );

    if (!mounted) return;
    setState(() {
      _isProcessingImages = true;
    });

    try {
      // Blur only when user taps "Blur Plates": process/store images on the server
      // and replace the local picks with server paths for preview + later attach.
      final local = _selectedImages.whereType<XFile>().toList();
      if (local.isEmpty) {
        if (!mounted) return;
        setState(() {
          _imagesProcessed = true;
        });
        return;
      }

      _debugLog('AI UI: Calling AiService.processCarImagesToServerPayload...');
      final payload = await AiService.processCarImagesToServerPayload(local);
      final paths = payload?['paths'] ?? const <String>[];
      final b64 = payload?['base64'] ?? const <String>[];

      if (paths.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to blur plates. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Build local preview files from base64 (avoids loading many /static/ URLs concurrently, which can drop connections)
      final List<XFile> blurredLocal = <XFile>[];
      final List<String> okPaths = <String>[];
      final parentState = context.findAncestorStateOfType<_SellCarPageState>();
      final draftId = parentState?._currentDraftId ?? 'default';
      try {
        final int n = paths.length;
        for (int i = 0; i < n; i++) {
          final String path = paths[i].toString();
          final String? dataUri = (i < b64.length) ? b64[i].toString() : null;
          if (dataUri != null &&
              dataUri.startsWith('data:') &&
              dataUri.contains('base64,')) {
            final idx = dataUri.indexOf('base64,');
            final raw = base64Decode(dataUri.substring(idx + 7));
            final stored = await SellDraftMediaPersistence.persistBytesToDraft(
              raw,
              draftId: draftId,
              namePrefix: 'listing_blur',
            );
            if (stored != null && stored.isNotEmpty) {
              blurredLocal.add(XFile(stored));
              okPaths.add(path);
            }
          } else if (i < local.length) {
            blurredLocal.add(local[i]);
          }
        }
      } catch (e) {
        _debugLog('AI UI: Failed to build local previews from base64: $e');
      }

      if (!mounted) return;
      setState(() {
        _selectedImages = blurredLocal.isNotEmpty
            ? blurredLocal
            : List<String>.from(paths);
        _imagesProcessed = true;
      });

      unawaited(_syncMediaDraftToParent());
      if (parentState != null) {
        parentState.carData['processed_image_paths'] = List<String>.from(
          okPaths.isNotEmpty ? okPaths : paths,
        );
        parentState.setState(() {});
        unawaited(parentState._saveSellDraftSnapshot());
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Plates blurred successfully.')));
    } catch (e) {
      _debugLog('AI UI: Error processing images: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error processing images: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isProcessingImages = false;
      });
    }
  }

  Future<void> _pickVideos() async {
    const maxDur = Duration(minutes: 5);
    try {
      List<XFile> picked;
      try {
        picked = await _imagePicker.pickMultiVideo(maxDuration: maxDur);
      } catch (_) {
        // Some platforms/plugins may not support multi-video selection.
        final single = await _imagePicker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: maxDur,
        );
        picked = single != null ? <XFile>[single] : <XFile>[];
      }
      if (picked.isEmpty || !mounted) return;
      setState(() {
        final existing = _selectedVideos.map((e) => e.path).toSet();
        for (final v in picked) {
          if (!existing.contains(v.path)) {
            _selectedVideos.add(v);
            existing.add(v.path);
          }
        }
      });
      unawaited(_syncMediaDraftToParent());
      unawaited(_saveDraft());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video selection failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B00).withOpacity(0.1), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B00).withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library, size: 48, color: Color(0xFFFF6B00)),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.addPhotos,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.addMorePhotos,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),

          // Image Processing Status
          if (_imagesProcessed)
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.blur_on, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      _trLegacyText(
                        context,
                        'Images Processed',
                        ar: 'تمت معالجة الصور',
                        ku: 'وێنەکان پرۆسێس کران',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _trLegacyText(
                          context,
                          'License plates have been blurred.',
                          ar: 'تم تمويه لوحات المركبات.',
                          ku: 'ژمارەی تابلۆکان شاردراون.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Photos Section — 2 per row, full width (like home listing cards), tap to open full-screen
          Text(
            _photosRequiredTitleGlobal(context),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 12),
          if (_selectedImages.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = 8.0;
                return GridView.builder(
                  key: ValueKey(
                    _selectedImages
                        .map((e) => e is XFile ? e.path : e.toString())
                        .join('|'),
                  ),
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    final image = _selectedImages[index];
                    final keyStr = image is XFile
                        ? image.path
                        : image.toString();
                    return Stack(
                      key: ValueKey(keyStr),
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ListingPreviewGalleryPage(
                                  imageFilesOrUrls: _selectedImages,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade700),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (image is XFile)
                                ? Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    key: ValueKey(image.path),
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade800,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white54,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : _listingNetworkImage(
                                    (image.toString().trim().startsWith('http'))
                                        ? image.toString().trim()
                                        : _buildFullImageUrl(image.toString()),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            unawaited(_syncMediaDraftToParent());
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.photo_library),
                  label: Text(
                    _selectedImages.isEmpty
                        ? AppLocalizations.of(context)!.addPhotos
                        : AppLocalizations.of(context)!.addMorePhotos,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _selectedImages.isNotEmpty && !_imagesProcessed
                    ? _processImages
                    : null,
                icon: _isProcessingImages
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_imagesProcessed ? Icons.check : Icons.blur_on),
                label: Text(
                  _isProcessingImages
                      ? _trLegacyText(
                          context,
                          'Processing...',
                          ar: '...جارٍ المعالجة',
                          ku: '...پرۆسێس دەکرێت',
                        )
                      : _imagesProcessed
                      ? _trLegacyText(
                          context,
                          'Processed',
                          ar: 'تمت المعالجة',
                          ku: 'پرۆسێس کرا',
                        )
                      : _trLegacyText(
                          context,
                          'Blur Plates',
                          ar: 'تمويه اللوحات',
                          ku: 'تابلۆ بشارەوە',
                        ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _imagesProcessed
                      ? Colors.green
                      : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Damage / crash photos (optional) — uploaded with kind=damage on submit
          Text(
            AppLocalizations.of(context)!.damageCrashPhotosSection,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 6),
          Text(
            _trLegacyText(
              context,
              'Shown next to title status on your listing. Not mixed into the main photo gallery.',
              ar: 'تظهر بجانب حالة الملكية في إعلانك. لا تُدمج مع معرض الصور الرئيسي.',
              ku: 'لەگەڵ دۆکی تایتڵ دەردەکەوێت، ناچێتە ناو گەلەری وێنەی سەرەکی.',
            ),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          SizedBox(height: 12),
          if (_damageImages.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                return GridView.builder(
                  key: ValueKey(
                    _damageImages
                        .map((e) => e is XFile ? e.path : e.toString())
                        .join('|'),
                  ),
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _damageImages.length,
                  itemBuilder: (context, index) {
                    final image = _damageImages[index];
                    final keyStr = image is XFile
                        ? image.path
                        : image.toString();
                    return Stack(
                      key: ValueKey('dmg_$keyStr'),
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ListingPreviewGalleryPage(
                                  imageFilesOrUrls: _damageImages,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.deepOrange.shade400,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (image is XFile)
                                ? Image.file(
                                    File(image.path),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    key: ValueKey(image.path),
                                  )
                                : _listingNetworkImage(
                                    (image.toString().trim().startsWith('http'))
                                        ? image.toString().trim()
                                        : _buildFullImageUrl(image.toString()),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _damageImages.removeAt(index);
                              });
                              unawaited(_syncMediaDraftToParent());
                              unawaited(_saveDraft());
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickDamageImages,
              icon: Icon(Icons.car_crash_outlined),
              label: Text(
                AppLocalizations.of(context)!
                    .addDamagePhotosCount(_damageImages.length),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade50,
                foregroundColor: Colors.deepOrange.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),

          // Videos Section — 2 per row like photos; tap opens full-screen PageView to swipe between videos
          Text(
            _videosOptionalTitleGlobal(context),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 12),
          if (_selectedVideos.isNotEmpty)
            GridView.builder(
              key: ValueKey(_selectedVideos.map((e) => e.path).join('|')),
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.25,
              ),
              itemCount: _selectedVideos.length,
              itemBuilder: (context, index) {
                final video = _selectedVideos[index];
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ListingPreviewGalleryPage(
                              imageFilesOrUrls: const [],
                              videoFilesOrUrls: List<dynamic>.from(
                                _selectedVideos,
                              ),
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade700),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FutureBuilder<String?>(
                          future: generateVideoThumbnail(video.path),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(snapshot.data!),
                                    fit: BoxFit.cover,
                                  ),
                                  Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: EdgeInsets.all(16),
                                      child: Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Container(
                              color: Colors.grey[800],
                              child: Center(
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedVideos.removeAt(index);
                          });
                          unawaited(_syncMediaDraftToParent());
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pickVideos,
              icon: Icon(Icons.videocam),
              label: Text(
                _selectedVideos.isEmpty
                    ? _trLegacyText(
                        context,
                        'Add Videos',
                        ar: 'إضافة فيديوهات',
                        ku: 'ڤیدیۆ زیاد بکە',
                      )
                    : _trLegacyText(
                        context,
                        'Add More Videos',
                        ar: 'إضافة المزيد من الفيديوهات',
                        ku: 'ڤیدیۆی زیاتر زیاد بکە',
                      ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.withOpacity(0.2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
                    unawaited(_syncMediaDraftToParent());
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
                      if (_selectedImages.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _pleaseSelectPhotoTextGlobal(context),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Save data and navigate to next step
                    unawaited(_syncMediaDraftToParent());
                      final parentState = context
                          .findAncestorStateOfType<_SellCarPageState>();
                      if (parentState != null) {
                      parentState.carData['images'] = List<dynamic>.from(
                        _selectedImages,
                      );
                      parentState.carData['damage_images'] =
                          List<dynamic>.from(_damageImages);
                      parentState.carData['videos'] = List<XFile>.from(
                        _selectedVideos,
                      );
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
    );
  }
}

/// One slot in the review-step media carousel (photo or video).
class _PreviewMediaEntry {
  const _PreviewMediaEntry({required this.isVideo, required this.item});
  final bool isVideo;
  final dynamic item;
}

// Preview of how the listing will look after submission (used in SellStep5).
class ListingPreviewWidget extends StatefulWidget {
  final Map<String, dynamic> carData;
  final List<dynamic> imageFilesOrUrls;

  /// When true, renders edge-to-edge like the real listing page (no rounded corners/border).
  final bool fullPage;

  const ListingPreviewWidget({
    super.key,
    required this.carData,
    required this.imageFilesOrUrls,
    this.fullPage = false,
  });

  @override
  State<ListingPreviewWidget> createState() => _ListingPreviewWidgetState();
}

class _ListingPreviewWidgetState extends State<ListingPreviewWidget> {
  final PageController _imagePageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = item is XFile ? item.path : item.toString().trim();
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  static String? _getFirstNonEmpty(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final String stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) return stringValue;
    }
    return null;
  }

  String _formatPrice(BuildContext context, String raw) {
    try {
      final num? value = num.tryParse(raw.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      if (value == null) return raw;
      final formatter = _decimalFormatterGlobal(context);
      return formatter.format(value);
    } catch (_) {
      return raw;
    }
  }

  Widget _buildSpecCard(_SpecItem item) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      constraints: BoxConstraints(minHeight: 84),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B00),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(item.icon, size: 16, color: Colors.black87),
              SizedBox(width: 6),
              Flexible(
                child: AutoSizeText(
                  item.label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textScaleFactor: 1.0,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.1,
                  ),
                  minFontSize: 7,
                  stepGranularity: 0.5,
                  overflow: TextOverflow.clip,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Colors.black.withOpacity(0.22),
            ),
          ),
          AutoSizeText(
            item.value!,
            maxLines: 2,
            textAlign: TextAlign.center,
            textScaleFactor: 1.0,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
            minFontSize: 10,
            stepGranularity: 0.5,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF3F3F3)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? const Color(0xFFE0E0E0) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.black),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? const Color(0xFF3A3A3A) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B00),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecsFromData(Map<String, dynamic> data) {
    final loc = AppLocalizations.of(context)!;
    final String? engineSize = _getFirstNonEmpty(data, [
      'engine_size',
      'engineSize',
      'engine',
    ]);
    final List<_SpecItem> primary = [
      _SpecItem(
        icon: Icons.speed,
        label: loc.mileageLabel,
        value: data['mileage'] != null
            ? '${_localizeDigitsGlobal(context, _formatPrice(context, data['mileage'].toString()))} ${loc.unit_km}'
            : null,
      ),
      _SpecItem(
        icon: Icons.settings_input_component,
        label: loc.detail_cylinders,
        value: () {
          final raw = _getFirstNonEmpty(data, [
            'cylinder_count',
            'cylinders',
            'cylinderCount',
          ]);
          if (raw == null) return null;
          return _localizeDigitsGlobal(context, raw);
        }(),
      ),
      _SpecItem(
        icon: Icons.straighten,
        label: loc.detail_engine,
        value: engineSize != null
            ? '${_localizeDigitsGlobal(context, engineSize.toString())}${loc.unit_liter_suffix}'
            : null,
      ),
      _SpecItem(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _SpecItem(
        icon: Icons.settings,
        label: loc.transmissionLabel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['transmission']),
        ),
      ),
      _SpecItem(
        icon: Icons.local_gas_station,
        label: loc.detail_fuel,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['fuel_type']),
        ),
      ),
    ];
    final List<Widget> details = [
      _detailRow(
        icon: Icons.layers,
        label: loc.trimLabel,
        value:
            _translateValueGlobal(context, _getFirstNonEmpty(data, ['trim'])) ??
            _getFirstNonEmpty(data, ['trim']),
      ),
      _detailRow(
        icon: Icons.check_circle,
        label: loc.detail_condition,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['condition']),
        ),
      ),
      _detailRow(
        icon: Icons.assignment_turned_in,
        label: loc.titleStatus,
        value: data['title_status'] != null
            ? (data['title_status'].toString().toLowerCase() == 'damaged'
                  ? (data['damaged_parts'] != null
                        ? loc.titleStatusDamagedWithParts(
                            _localizeDigitsGlobal(
                              context,
                              data['damaged_parts'].toString(),
                            ),
                          )
                        : loc.value_title_damaged)
                  : loc.value_title_clean)
            : null,
      ),
      _detailRow(
        icon: Icons.drive_eta,
        label: loc.detail_drive,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, [
            'drive_type',
            'driveType',
            'drivetrain',
            'drive',
          ]),
        ),
      ),
      _detailRow(
        icon: Icons.directions_car_filled,
        label: loc.detail_body,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['body_type', 'bodyType', 'body']),
        ),
      ),
      _detailRow(
        icon: Icons.color_lens,
        label: loc.detail_color,
        value: _translateValueGlobal(
          context,
          _getFirstNonEmpty(data, ['color']),
        ),
      ),
      _detailRow(
        icon: Icons.airline_seat_recline_normal,
        label: loc.detail_seating,
        value: _localizeDigitsGlobal(
          context,
          _getFirstNonEmpty(data, ['seating', 'seats', 'seatCount']) ?? '',
        ),
      ),
      _detailRow(
        icon: Icons.phone,
        label: loc.phoneLabel,
        value: _getFirstNonEmpty(data, ['contact_phone']),
      ),
      _detailRow(
        icon: Icons.pin_outlined,
        label: 'VIN',
        value: _getFirstNonEmpty(data, ['vin']),
      ),
    ];
    final primItems = primary
        .where((i) => i.value != null && i.value!.isNotEmpty)
        .toList();
    final primGrid = GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: primItems.length,
      itemBuilder: (context, index) => _buildSpecCard(primItems[index]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [primGrid, SizedBox(height: 12), ...details],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.carData;
    final images = widget.imageFilesOrUrls;
    final dynamic rawVideos = data['videos'];
    final List<dynamic> videos = rawVideos is List ? rawVideos : const [];
    final List<_PreviewMediaEntry> media = [
      ...images.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...videos.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
    final hasMedia = media.isNotEmpty;

    final String title = (data['title']?.toString() ?? '').trim().isNotEmpty
        ? data['title'].toString().trim()
        : '${data['brand'] ?? ''} ${data['model'] ?? ''} ${data['trim'] ?? ''}'
              .trim();
    final String yearStr = data['year'] != null ? data['year'].toString() : '';
    final String titleWithYear = yearStr.isNotEmpty
        ? '$title ($yearStr)'
        : (title.isEmpty ? 'Your listing' : title);

    final bool fullPage = widget.fullPage;
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: fullPage ? BorderRadius.zero : BorderRadius.circular(16),
        border: fullPage ? null : Border.all(color: Colors.grey[700]!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo + video carousel — tap: images open gallery, videos open preview/player
          SizedBox(
            height: fullPage ? 300 : 260,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasMedia)
                  GestureDetector(
                    onTap: () => _openCarouselDetail(context, media, images),
                    child: PageView.builder(
                      controller: _imagePageController,
                      onPageChanged: (idx) =>
                          setState(() => _currentMediaIndex = idx),
                      itemCount: media.length,
                      itemBuilder: (context, index) {
                        final slot = media[index];
                        if (slot.isVideo) {
                          return _buildVideoCarouselSlide(slot.item);
                        }
                        final item = slot.item;
                        if (item is XFile) {
                          return Image.file(
                            File(item.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        }
                        final url = item.toString().trim();
                        final fullUrl = url.startsWith('http')
                            ? url
                            : _buildFullImageUrl(url);
                        return _listingNetworkImage(
                          fullUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        );
                      },
                    ),
                  )
                else
                  Container(
                    color: Colors.grey[800],
                    child: Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Colors.grey[500],
                    ),
                  ),
                if (hasMedia && media.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(media.length, (i) {
                          final active = i == _currentMediaIndex;
                          return AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            margin: EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 10 : 6,
                            height: active ? 10 : 6,
                            decoration: BoxDecoration(
                              color: active ? Colors.white : Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Content (title, price, specs)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['is_quick_sell'] == true ||
                    data['is_quick_sell'] == 'true')
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange, Colors.deepOrange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flash_on, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.quickSell,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  titleWithYear,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                if (data['price'] != null &&
                    data['price'].toString().trim().isNotEmpty)
                  Text(
                    _formatCurrencyGlobal(context, data['price']),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                SizedBox(height: 16),
                Divider(height: 1, thickness: 1, color: Colors.white24),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.specificationsLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B00),
                  ),
                ),
                SizedBox(height: 12),
                _buildSpecsFromData(data),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sellReviewListingBrand(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final locBrand = CarNameTranslations.getLocalizedBrand(
    context,
    brand.isEmpty ? null : brand,
  );
  if (locBrand.isNotEmpty) return locBrand;
  return (car['title'] ?? '').toString().trim();
}

String _sellReviewListingModel(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  final localizedModel = CarNameTranslations.getLocalizedModel(
    context,
    brand.isEmpty ? null : brand,
    model.isEmpty ? null : model,
  );
  final displayModel = localizedModel.isNotEmpty ? localizedModel : model;
  final year = (car['year'] ?? '').toString().trim();
  if (displayModel.isEmpty) return year;
  if (year.isEmpty) return displayModel;
  return '$displayModel $year';
}

bool _sellReviewHasPrice(Map<String, dynamic> car) {
  final p = car['price'];
  if (p == null) return false;
  return p.toString().trim().isNotEmpty;
}

/// Sell step 5 preview: matches [CarDetailsPage] layout and light/dark theming.
class SellReviewCarDetailScrollView extends StatefulWidget {
  const SellReviewCarDetailScrollView({super.key, required this.carData});

  final Map<String, dynamic> carData;

  @override
  State<SellReviewCarDetailScrollView> createState() =>
      _SellReviewCarDetailScrollViewState();
}

class _SellReviewCarDetailScrollViewState
    extends State<SellReviewCarDetailScrollView> {
  final PageController _pageController = PageController();
  int _currentMediaIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<_PreviewMediaEntry> _buildMediaList() {
    final imgs = widget.carData['images'];
    final vids = widget.carData['videos'];
    final il = imgs is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(imgs),
          )
        : const <dynamic>[];
    final vl = vids is List
        ? SellDraftMediaPersistence.resolveDynamicMediaList(
            List<dynamic>.from(vids),
          )
        : const <dynamic>[];
    return [
      ...il.map((e) => _PreviewMediaEntry(isVideo: false, item: e)),
      ...vl.map((e) => _PreviewMediaEntry(isVideo: true, item: e)),
    ];
  }

  void _openCarouselDetail(
    BuildContext context,
    List<_PreviewMediaEntry> media,
    List<dynamic> images,
  ) {
    if (media.isEmpty) return;
    final i = _currentMediaIndex.clamp(0, media.length - 1);
    final videos = media.where((m) => m.isVideo).map((m) => m.item).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingPreviewMediaGridPage(
          imageFilesOrUrls: images,
          videoFilesOrUrls: videos,
          initialIndex: i,
        ),
      ),
    );
  }

  Widget _buildVideoCarouselSlide(dynamic item) {
    final String path = item is XFile ? item.path : item.toString().trim();
    final bool isLocalFile =
        path.isNotEmpty &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isLocalFile)
          FutureBuilder<String?>(
            future: generateVideoThumbnail(path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              }
              return Container(
                color: Colors.grey[850],
                child: Center(
                  child: Icon(Icons.videocam, color: Colors.white70, size: 48),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[850],
            child: Center(
              child: Icon(Icons.videocam, color: Colors.white70, size: 56),
            ),
          ),
        Center(
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final car = widget.carData;
    final media = _buildMediaList();
    final brandStr = _sellReviewListingBrand(context, car);
    final modelStr = _sellReviewListingModel(context, car);
    final rawImages = car['images'] is List ? (car['images'] as List) : [];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (media.isEmpty)
                    Container(
                      color: Colors.grey[900],
                      child: Icon(
                        Icons.directions_car,
                        size: 60,
                        color: Colors.grey[400],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () =>
                          _openCarouselDetail(context, media, rawImages),
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (idx) =>
                            setState(() => _currentMediaIndex = idx),
                        itemCount: media.length,
                        itemBuilder: (context, index) {
                          final slot = media[index];
                          if (slot.isVideo) {
                            return _buildVideoCarouselSlide(slot.item);
                          }
                          final item = slot.item;
                          if (item is XFile) {
                            return Image.file(
                              File(item.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[900],
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                              ),
                            );
                          }
                          final url = item.toString().trim();
                          final fullUrl = url.startsWith('http')
                              ? url
                              : _buildFullImageUrl(url);
                          return _listingNetworkImage(
                            fullUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        },
                      ),
                    ),
                  if (media.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(media.length, (i) {
                                final active = i == _currentMediaIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: active ? 10 : 6,
                                  height: active ? 10 : 6,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white
                                        : Colors.white70,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isLightShell
                  ? AppThemes.lightAppBackground
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Theme(
              data: isLightShell ? Theme.of(context) : AppThemes.darkTheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (car['is_quick_sell'] == true ||
                      car['is_quick_sell'] == 'true')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.flash_on,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)!.quickSell,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              brandStr,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_sellReviewHasPrice(car) && modelStr.isEmpty) ...[
                            const SizedBox(width: 12),
                            Text(
                              _formatCurrencyGlobal(context, car['price']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF6B00),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (modelStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                modelStr,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: isLightShell
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_sellReviewHasPrice(car)) ...[
                              const SizedBox(width: 12),
                              Text(
                                _formatCurrencyGlobal(context, car['price']),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF6B00),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                  // Match Home listing card: city / uploaded info goes below title + price.
                  Builder(
                    builder: (context) {
                      String? pickCity(List<String> keys) {
                        for (final k in keys) {
                          final v = car[k]?.toString().trim();
                          if (v != null && v.isNotEmpty) return v;
                        }
                        return null;
                      }

                      final cityDetail = (pickCity(['city', 'location']) ?? '')
                          .trim();
                      final uploadedDetail = _listingUploadedAgo(context, car);
                      if (cityDetail.isEmpty && uploadedDetail.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final cityLabelStyle = TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isLightShell
                            ? const Color(0xFF757575)
                            : Colors.white70,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: cityDetail.isEmpty
                                  ? const SizedBox.shrink()
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_city,
                                          size: 14,
                                          color: isLightShell
                                              ? const Color(0xFF757575)
                                              : Colors.white70,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '${AppLocalizations.of(context)!.cityLabel}: ${_translateValueGlobal(context, pickCity(['city', 'location'])) ?? pickCity(['city', 'location'])}',
                                            style: cityLabelStyle,
                                            // Allow long cities like "Sulaymaniyah" to show fully.
                                            maxLines: 2,
                                            overflow: TextOverflow.clip,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            if (uploadedDetail.isNotEmpty) ...[
                              if (cityDetail.isNotEmpty)
                                const SizedBox(width: 8),
                              Text(
                                uploadedDetail,
                                style: cityLabelStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isLightShell
                        ? const Color(0xFFE0E0E0)
                        : Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.specificationsLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B00),
                    ),
                  ),
                  const SizedBox(height: 20),
                  buildCarListingSpecsGrid(context, car),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Step 5: Review & Submit
class SellStep5Page extends StatefulWidget {
  const SellStep5Page({super.key});
  @override
  _SellStep5PageState createState() => _SellStep5PageState();
}

class _SellStep5PageState extends State<SellStep5Page> {
  bool isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final carData = parentState?.carData ?? {};
    final isLight = Theme.of(context).brightness == Brightness.light;
    final shellBg = isLight
        ? Colors.white
        : Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: shellBg,
      child: Column(
        children: [
          Expanded(child: SellReviewCarDetailScrollView(carData: carData)),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: shellBg,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                        child: OutlinedButton(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                final parentState = context
                                    .findAncestorStateOfType<
                                      _SellCarPageState
                                    >();
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
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setState(() {
                                  isSubmitting = true;
                                });

                                try {
                                  // Client-side validation before submit
                                  final parentState = context
                                      .findAncestorStateOfType<
                                        _SellCarPageState
                                      >();
                                  final Map<String, dynamic> carData =
                                      Map<String, dynamic>.from(
                                        parentState?.carData ?? {},
                                      );
                                  final List<String> required = [
                                    'brand',
                                    'model',
                                    'trim',
                                    'year',
                                    'mileage',
                                    'condition',
                                    'transmission',
                                    'fuel_type',
                                    'color',
                                    'body_type',
                                    'seating',
                                    'drive_type',
                                    'region_specs',
                                    'title_status',
                                  ];
                                  final List<String> missing = [];
                                  for (final k in required) {
                                    final v = carData[k];
                                    final isEmpty =
                                        v == null ||
                                        (v is String && v.trim().isEmpty);
                                    if (isEmpty) missing.add(k);
                                  }
                                  if (missing.isNotEmpty) {
                                    int stepFor(String k) {
                                      const step1 = {
                                        'brand',
                                        'model',
                                        'trim',
                                        'year',
                                      };
                                      const step2 = {
                                        'mileage',
                                        'condition',
                                        'transmission',
                                        'fuel_type',
                                        'color',
                                        'body_type',
                                        'seating',
                                        'drive_type',
                                        'region_specs',
                                        'title_status',
                                      };
                                      if (step1.contains(k)) return 1;
                                      if (step2.contains(k)) return 2;
                                      return 3;
                                    }

                                    final first = missing.first;
                                    final targetStep = stepFor(first);
                                    // Navigate user to the step containing the first missing field
                                    if (parentState != null) {
                                      parentState._jumpSellWizardToIndex(
                                        targetStep - 1,
                                      );
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Please complete: ${missing.join(', ')}',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    setState(() {
                                      isSubmitting = false;
                                    });
                                    return;
                                  }
                                  // Submit the listing
                                  final submittedId = await _submitListing(
                                    carData,
                                    parentState: parentState,
                                  );
                                  if (!mounted) return;

                                  if (parentState?._isEditMode == true) {
                                    Map<String, dynamic> updatedCar =
                                        Map<String, dynamic>.from(carData);
                                    if ((submittedId ?? '').isNotEmpty) {
                                      try {
                                        final fresh = await ApiService.getCar(
                                          submittedId!,
                                        );
                                        final inner = fresh['car'];
                                        if (inner is Map) {
                                          updatedCar =
                                              Map<String, dynamic>.from(
                                            inner.cast<String, dynamic>(),
                                          );
                                        }
                                      } catch (_) {
                                        updatedCar['id'] = submittedId;
                                        updatedCar['public_id'] = submittedId;
                                      }
                                    }
                                    try {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)!
                                                .saveChangesButton,
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (_) {}
                                    Navigator.pop(
                                      context,
                                      {'car': updatedCar},
                                    );
                                    return;
                                  }

                                  if (parentState != null) {
                                    await parentState._clearSubmittedDraftOnly(
                                      draftId: parentState._currentDraftId,
                                    );
                                  } else {
                                    final sp = await SharedPreferences.getInstance();
                                    String draftId = '';
                                    final activeRaw =
                                        sp.getString('legacy_sell_draft_snapshot_v1');
                                    if (activeRaw != null && activeRaw.trim().isNotEmpty) {
                                      try {
                                        final decoded = json.decode(activeRaw);
                                        if (decoded is Map) {
                                          draftId =
                                              (decoded['draftId'] ?? '').toString().trim();
                                        }
                                      } catch (_) {}
                                    }
                                    await sp.remove('legacy_sell_draft_current_step_v1');
                                    await sp.remove('legacy_sell_draft_snapshot_v1');
                                    await sp.remove('legacy_sell_draft_step1_v1');
                                    await sp.remove('legacy_sell_draft_step2_v1');
                                    await sp.remove('legacy_sell_draft_step3_v1');
                                    await sp.remove('legacy_sell_draft_step4_v1');
                                    if (draftId.isNotEmpty) {
                                      final archive = _decodeSellDraftArchive(
                                        sp.getString(_sellDraftArchiveKey),
                                      );
                                      archive.removeWhere(
                                        (item) => item['draftId']?.toString() == draftId,
                                      );
                                      await sp.setString(
                                        _sellDraftArchiveKey,
                                        _encodeSellDraftArchive(archive),
                                      );
                                    }
                                  }

                                  // Show success message
                                  if (!mounted) return;
                                  try {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _listingSubmittedSuccessTextGlobal(
                                            context,
                                          ),
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (_) {}

                                  // Navigate back to home
                                  try {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pushNamedAndRemoveUntil(
                                      '/',
                                      (route) => false,
                                    );
                                  } catch (_) {
                                    // Fallback
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/',
                                    );
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        userErrorText(
                                          context,
                                          e,
                                          fallback: AppLocalizations.of(
                                            context,
                                          )!.couldNotSubmitListing,
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  setState(() {
                                    isSubmitting = false;
                                  });
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
                        child: isSubmitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                parentState?._isEditMode == true
                                    ? AppLocalizations.of(context)!
                                        .saveChangesButton
                                    : AppLocalizations.of(context)!
                                        .submitListing,
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
            ),
          ),
        ],
      ),
    );
  }

  /// PUT payload for editing an existing listing (matches backend updatable fields).
  Map<String, dynamic> _buildCarUpdatePayload(Map<String, dynamic> carData) {
    final brand = carData['brand']?.toString() ?? '';
    final model = carData['model']?.toString() ?? '';
    final trim = carData['trim']?.toString() ?? 'Base';
    final year =
        int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
    final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
    final condition =
        (carData['condition']?.toString() ?? 'used').toLowerCase();
    final transmission =
        (carData['transmission']?.toString() ?? 'automatic').toLowerCase();
    final fuelType =
        (carData['fuel_type']?.toString() ?? 'gasoline').toLowerCase();
    final color = (carData['color']?.toString() ?? 'black').toLowerCase();
    final bodyType = (carData['body_type']?.toString() ?? 'sedan').toLowerCase();
    final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
    final driveType = (carData['drive_type']?.toString() ?? 'fwd').toLowerCase();
    final regionSpecsRaw =
        carData['region_specs']?.toString().trim().toLowerCase() ?? '';
    final regionSpecs =
        isValidCarRegionSpecCode(regionSpecsRaw) ? regionSpecsRaw : null;
    final titleStatus =
        (carData['title_status']?.toString() ?? 'clean').toLowerCase();
    final damagedParts = titleStatus == 'damaged'
        ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
        : null;
    final cylinderCount = int.tryParse(
      carData['cylinder_count']?.toString() ?? '',
    );
    final engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
    final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
        double.tryParse(engineSizeRaw);
    final priceStr = (carData['price']?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9\.-]'),
      '',
    );
    final dynamic priceValue = priceStr.isEmpty
        ? null
        : (int.tryParse(priceStr) ?? double.tryParse(priceStr));
    final location = (carData['location']?.toString().trim().isNotEmpty == true)
        ? carData['location'].toString().trim()
        : (carData['city']?.toString().trim() ?? '');
    final plateType =
        (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
    final plateCity = (carData['plate_city']?.toString() ?? '').trim();
    final fuelEconomy = (carData['fuel_economy']?.toString() ?? '').trim();
    final description = (carData['description']?.toString() ?? '').trim();

    return {
      'title': '$brand $model $trim'.trim(),
      'brand': brand.toLowerCase().replaceAll(' ', '-'),
      'model': model,
      'trim': trim,
      'year': year,
      'price': priceValue,
      'mileage': mileage,
      'condition': condition,
      'transmission': transmission,
      'engine_type': fuelType,
      'fuel_type': fuelType,
      'color': color,
      'body_type': bodyType,
      'seating': seating,
      'drive_type': driveType,
      'region_specs': regionSpecs,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'cylinder_count': cylinderCount,
      'engine_size': engineSize,
      'location': location,
      'plate_type': plateType.isNotEmpty ? plateType : null,
      'plate_city': plateCity.isNotEmpty ? plateCity : null,
      if (fuelEconomy.isNotEmpty) 'fuel_economy': fuelEconomy,
      if (description.isNotEmpty) 'description': description,
      if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
        'vin': carData['vin'].toString().trim(),
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
  }

  /// Returns the created car id on success so caller can navigate to listing page; null otherwise.
  Future<String?> _submitListing(
    Map<String, dynamic> carData, {
    _SellCarPageState? parentState,
  }) async {
    // Require authentication before allowing submission
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw Exception('Authentication required');
    }

    final brand = carData['brand']?.toString() ?? '';
    final model = carData['model']?.toString() ?? '';
    final trim = carData['trim']?.toString() ?? 'Base';
    final year =
        int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
    final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
    final condition = (carData['condition']?.toString() ?? 'Used')
        .toLowerCase();
    final transmission = (carData['transmission']?.toString() ?? 'Automatic')
        .toLowerCase();
    final fuelType = (carData['fuel_type']?.toString() ?? 'Gasoline')
        .toLowerCase();
    final color = (carData['color']?.toString() ?? 'Black').toLowerCase();
    final bodyType = (carData['body_type']?.toString() ?? 'Sedan')
        .toLowerCase();
    final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
    final driveType = (carData['drive_type']?.toString() ?? 'fwd')
        .toLowerCase();
    final regionSpecsRaw =
        carData['region_specs']?.toString().trim().toLowerCase() ?? '';
    final regionSpecs = isValidCarRegionSpecCode(regionSpecsRaw)
        ? regionSpecsRaw
        : null;
    final titleStatus = (carData['title_status']?.toString() ?? 'clean')
        .toLowerCase();
    final damagedParts = titleStatus == 'damaged'
        ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
        : null;
    final cylinderCount = int.tryParse(
      carData['cylinder_count']?.toString() ?? '',
    );
    final String engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
    final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
        double.tryParse(engineSizeRaw);
    final price = int.tryParse(carData['price']?.toString() ?? '');
    final city = (carData['city']?.toString() ?? 'Baghdad').toLowerCase();
    final plateType =
        (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
    // Keep city casing as selected in UI; some backends validate against
    // a specific list and may reject lowercased values silently.
    final plateCity = (carData['plate_city']?.toString() ?? '').trim();
    final title = '$brand $model $trim'.trim();

    // Normalize payload to match backend expectations
    final String priceStr = (carData['price']?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9\.-]'),
      '',
    );
    final dynamic priceValue = priceStr.isEmpty
        ? null
        : (int.tryParse(priceStr) ?? double.tryParse(priceStr) ?? price);
    // Keep `engine_type` and `fuel_type` independent. Some older backends treated
    // these as aliases, but overwriting `fuel_type` with `engine_type` can flip
    // the user's selection (e.g. Gasoline → Diesel).
    // In this sell flow, "engine type" uses the same vocabulary as fuel type.
    // Keep them in sync to avoid mismatches across backend variants / UI surfaces.
    final String engineType = fuelType;
    final String location = (carData['location']?.toString() ?? city)
        .toString();

    final payload = {
      'title': title,
      'brand': brand.toLowerCase().replaceAll(' ', '-'),
      'model': model,
      'trim': trim,
      'year': year,
      'price': priceValue,
      'mileage': mileage,
      'condition': condition,
      'transmission': transmission,
      // Send both keys so either backend variant accepts the fields.
      'engine_type': engineType.isNotEmpty ? engineType : null,
      'fuel_type': fuelType.isNotEmpty ? fuelType : null,
      'color': color,
      'body_type': bodyType,
      'seating': seating,
      'drive_type': driveType,
      'region_specs': regionSpecs,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'cylinder_count': cylinderCount,
      'engine_size': engineSize,
      'location': location,
      'city': city,
      'plate_type': plateType.isNotEmpty ? plateType : null,
      // Send both snake_case and camelCase so either backend schema accepts it.
      'plateType': plateType.isNotEmpty ? plateType : null,
      'plate_city': plateCity.isNotEmpty ? plateCity : null,
      'plateCity': plateCity.isNotEmpty ? plateCity : null,
      'contact_phone': (carData['contact_phone']?.toString() ?? '').trim(),
      'description': (carData['description']?.toString() ?? '').trim(),
      'is_quick_sell': carData['is_quick_sell'] ?? false,
      if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
        'vin': carData['vin'].toString().trim(),
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $existingToken',
      };
      final editId = context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._editListingId
              ?.trim() ??
          '';

      http.Response? response;
      String carId = '';
      if (editId.isNotEmpty) {
        try {
          await ApiService.updateCar(editId, _buildCarUpdatePayload(carData));
          carId = editId;
        } on ApiException catch (e) {
          throw Exception(e.message);
        }
      } else {
        final url = Uri.parse('${getApiBase()}/api/cars');
        response = await http
            .post(url, headers: headers, body: json.encode(payload))
            .timeout(
              const Duration(seconds: 25),
              onTimeout: () {
                throw Exception(
                  'Network timeout. Please check the server and try again.',
                );
              },
            );
        if (response.statusCode == 201) {
          final Map<String, dynamic> created = json.decode(response.body);
          final dynamic carObj =
              (created['car'] is Map) ? created['car'] : created;
          carId = (carObj['id']?.toString() ?? '').toString();
        }
      }

      if (carId.isNotEmpty) {
        // Success - listing created or updated
        // Upload/attach images and wait for list refresh so the new listing has all image URLs before we show success
        try {
          final draftId = parentState?._currentDraftId.isNotEmpty == true
              ? parentState!._currentDraftId
              : 'default';
          final storedMedia =
              await SellDraftMediaPersistence.prepareCarDataForStorage(
            carData,
            draftId: draftId,
          );
          carData['images'] = storedMedia['images'];
          carData['damage_images'] = storedMedia['damage_images'];
          carData['videos'] = storedMedia['videos'];
          if (parentState != null && parentState.mounted) {
            parentState.setState(() {
              parentState.carData['images'] = carData['images'];
              parentState.carData['damage_images'] = carData['damage_images'];
              parentState.carData['videos'] = carData['videos'];
            });
          }

          final dynamic maybeImgs = carData['images'];
          final List<dynamic> imgs = (maybeImgs is List) ? maybeImgs : const [];
          final dynamic maybeVideos = carData['videos'];
          final List<dynamic> vids = (maybeVideos is List)
              ? maybeVideos
              : const [];
          final List<XFile> toUpload = <XFile>[];
          final List<String> toAttach = <String>[];
          final List<XFile> videosToUpload =
              SellDraftMediaPersistence.xFilesForUpload(vids);
          for (final dynamic img in imgs) {
            if (img is XFile) {
              if (File(img.path).existsSync()) {
                toUpload.add(img);
              }
            } else if (img is String) {
              final s = img.trim();
              // If it's a server-relative path (from "Blur Plates"), attach it; don't treat it as a local file.
              if (s.startsWith('uploads/') ||
                  s.startsWith('static/') ||
                  s.startsWith('/static/')) {
                toAttach.add(s);
              } else if (s.startsWith('http://') || s.startsWith('https://')) {
                // We don't attach absolute URLs; if you ever store them, keep them as-is in DB via other flow.
                // For now, ignore.
              } else if (File(s).existsSync()) {
                toUpload.add(XFile(s));
              }
            }
          }
          if (toAttach.isNotEmpty) {
            await CarService().attachCarImages(carId, toAttach);
          } else if (toUpload.isNotEmpty) {
            // No blur on submit; backend is called with skip_blur=1
            await CarService().uploadCarImages(carId, toUpload);
          }
          if (videosToUpload.isNotEmpty) {
            // Backend (kk/routes/media.py) expects multipart field name "files", not "video".
            final url = Uri.parse('${getApiBase()}/api/cars/$carId/videos');
            final req = http.MultipartRequest('POST', url);
            req.headers['Authorization'] = 'Bearer $existingToken';
            for (final v in videosToUpload) {
              req.files.add(await _buildVideoMultipartFile(v));
            }
            final resp = await req.send();
            final respBody = await resp.stream.bytesToString();
            Map<String, dynamic> payload = const {};
            try {
              final parsed = json.decode(respBody);
              if (parsed is Map<String, dynamic>) payload = parsed;
            } catch (_) {}
            final uploaded = payload['videos'];
            final uploadedCount = uploaded is List ? uploaded.length : 0;
            if (resp.statusCode != 200 && resp.statusCode != 201) {
              _debugLog('Video upload failed: ${resp.statusCode} $respBody');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Video upload failed (${resp.statusCode}). ${respBody.isNotEmpty ? respBody : ''}',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } else if (uploadedCount == 0) {
              _debugLog(
                'Video upload returned success but 0 videos: $respBody',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      (payload['message'] ?? 'No valid videos were uploaded.')
                          .toString(),
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          }
          final dynamic maybeDmg = carData['damage_images'];
          final List<dynamic> dimgs =
              (maybeDmg is List) ? maybeDmg : const [];
          final List<XFile> damageToUpload = <XFile>[];
          final List<String> damageToAttach = <String>[];
          for (final dynamic img in dimgs) {
            if (img is XFile) {
              if (File(img.path).existsSync()) {
                damageToUpload.add(img);
              }
            } else if (img is String) {
              final s = img.trim();
              if (s.startsWith('uploads/') ||
                  s.startsWith('static/') ||
                  s.startsWith('/static/')) {
                damageToAttach.add(s);
              } else if (s.startsWith('http://') || s.startsWith('https://')) {
                // Skip absolute URLs for attach/upload here.
              } else if (File(s).existsSync()) {
                damageToUpload.add(XFile(s));
              }
            }
          }
          if (damageToAttach.isNotEmpty) {
            await CarService().attachCarImages(
              carId,
              damageToAttach,
              kind: 'damage',
            );
          }
          if (damageToUpload.isNotEmpty) {
            await CarService().uploadCarImages(
              carId,
              damageToUpload,
              imageKind: 'damage',
            );
          }
          // Refresh list so new listing has server-confirmed image_url/images before success/navigation
          try {
            await CarService().getCars(refresh: true);
          } catch (_) {}
          // Precache all listing images so they appear instantly when user views the listing (no placeholder wait)
          if (mounted) {
            final svc = CarService();
            final createdCar = svc.cars
                .where((c) => c['id']?.toString() == carId)
                .toList();
            final Map<String, dynamic>? car = createdCar.isNotEmpty
                ? createdCar.first
                : null;
            if (car != null) {
              final List<String> urls = <String>[];
              final String primary = (car['image_url'] ?? '').toString();
              final List<dynamic> imgs = (car['images'] is List)
                  ? (car['images'] as List)
                  : const [];
              if (primary.isNotEmpty) urls.add(_buildFullImageUrl(primary));
              for (final dynamic it in imgs) {
                if (it is Map &&
                    (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
                  continue;
                }
                final String s = it is Map
                    ? (it['image_url'] ??
                              it['url'] ??
                              it['path'] ??
                              it['src'] ??
                              '')
                          .toString()
                    : it.toString();
                if (s.isNotEmpty) {
                  final full = _buildFullImageUrl(s);
                  if (!urls.contains(full)) urls.add(full);
                }
              }
              if (urls.isEmpty && imgs.isNotEmpty) {
                dynamic first;
                for (final dynamic e in imgs) {
                  if (e is Map &&
                      (e['kind'] ?? '').toString().toLowerCase() == 'damage') {
                    continue;
                  }
                  first = e;
                  break;
                }
                if (first != null) {
                  final String s = first is Map
                      ? (first['image_url'] ??
                                first['url'] ??
                                first['path'] ??
                                first['src'] ??
                                '')
                            .toString()
                      : first.toString();
                  if (s.isNotEmpty) urls.add(_buildFullImageUrl(s));
                }
              }
              for (final url in urls) {
                if (url.isEmpty || !mounted) continue;
                try {
                  await precacheImage(NetworkImage(url), context);
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.listingUploadPartialFail(e.toString()),
                ),
              ),
            );
          } catch (_) {}
        }
        _debugLog(
          editId.isNotEmpty
              ? 'Listing updated successfully'
              : 'Listing created successfully',
        );
        return carId;
      }

      // Edit failures throw via [ApiException] above; only create reaches here.
      final createResponse = response;
      if (createResponse == null) {
        throw Exception('Failed to create listing');
      }
      if (createResponse.statusCode == 401) {
        _debugLog('Submission failed: Authentication failed');
        throw Exception('Authentication failed. Please log in again.');
      } else {
        _debugLog(
          'Submission failed: ${createResponse.statusCode} - ${createResponse.body}',
        );
        dynamic errorData;
        try {
          errorData = json.decode(createResponse.body);
        } catch (_) {
          errorData = null;
        }
        String? msg;
        if (errorData is Map<String, dynamic>) {
          final List<dynamic>? errs = (errorData['errors'] is List)
              ? List<dynamic>.from(errorData['errors'])
              : null;
          if (errs != null && errs.isNotEmpty) {
            msg = errs.map((e) => e.toString()).join(', ');
          } else {
            msg =
                (errorData['message']?.toString()) ??
                (errorData['error']?.toString());
          }
        } else if (errorData is List) {
          msg = errorData.map((e) => e.toString()).join(', ');
        }
        throw Exception(msg ?? 'Failed to create listing');
      }
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException')) {
        throw Exception('Network error. Please check your connection.');
      }
      rethrow;
    }
  }
}

