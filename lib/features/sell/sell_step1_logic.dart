part of 'sell_flow.dart';

mixin _SellStep1Logic on _SellStep1Fields {
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
        _SellStep1Fields._draftKey,
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
    } catch (e, st) { logNonFatal(e, st); }
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
                  color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.25),
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
                key: ValueKey(
                  'cat_year_${_catYear ?? years.first}_${years.join('-')}',
                ),
                isExpanded: true,
                initialValue: _catYear != null && years.contains(_catYear)
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
                          fillColor: Colors.black.withValues(alpha: 0.2),
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
                        separatorBuilder: (context, index) => SizedBox(height: 10),
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
              backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
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
                        fillColor: Colors.black.withValues(alpha: 0.2),
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
                                color: Colors.black.withValues(alpha: 0.15),
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

}
