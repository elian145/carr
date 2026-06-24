part of 'sell_flow.dart';

mixin _SellStep1PickersTrim on _SellStep1Catalog {
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
}
