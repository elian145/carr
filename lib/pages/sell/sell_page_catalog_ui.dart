part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member

extension SellPageCatalogUi on _SellPageState {
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.28),
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
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
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
              onPressed:
                  (_catalogYear != null &&
                      (preview != null || unionPreview != null) &&
                      !_submitting)
                  ? _applyCatalogSpecs
                  : null,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: Text(
                _text(
                  'Apply to form below',
                  ar: 'تطبيق على النموذج أدناه',
                  ku: 'جێبەجێکردن لەسەر فۆڕمی خوارەوە',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
