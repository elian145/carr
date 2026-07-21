part of 'sell_flow.dart';

mixin _SellStep1PickersTrim on _SellStep1Catalog {
  Widget _buildTrimCatalogSection() {
    final trim = (selectedTrim ?? '').trim();
    if (trim.isEmpty) return const SizedBox.shrink();
    final b = selectedBrand;
    final m = selectedModel;
    if (b == null || m == null) return const SizedBox.shrink();

    if (!_specDbReady) {
      return FilterCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.loadingVehicleSpecs,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_specIdx == null) {
      return FilterCard(
        isError: true,
        child: Text(
          _specLoadErr ??
              AppLocalizations.of(context)!.specDatabaseUnavailableRestartTheAppAfterFlutterPubGet,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      );
    }
    if (!_specIdx!.hasCoverage(b, m)) {
      return const SizedBox.shrink();
    }

    final idx = _specIdx!;
    final variants = idx.variantsForAppModel(b, m);
    if (variants.isEmpty) return const SizedBox.shrink();

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

    final style = filterDialogStyle(context);
    final canApply = preview != null || unionPreview != null;

    String? previewSummary;
    if (preview != null) {
      previewSummary = [
        _translateValueGlobal(context, preview.engineType) ?? preview.engineType,
        _translateValueGlobal(context, preview.transmission) ??
            preview.transmission,
        _translateValueGlobal(context, preview.driveType) ?? preview.driveType,
        _translateValueGlobal(context, preview.bodyType) ?? preview.bodyType,
      ].where((s) => s.trim().isNotEmpty).join(' · ');
    }

    return FilterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context)!.catalogAutoFill,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: style.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.selectAModelYearToLoadMatchingSpecs,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Colors.grey[600],
            ),
          ),
          if (years.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              key: ValueKey(
                'cat_year_${_catYear ?? years.first}_${years.join('-')}',
              ),
              isExpanded: true,
              isDense: true,
              menuMaxHeight: filterDropdownMenuMaxHeight(context),
              dropdownColor: style.menuFill,
              initialValue: _catYear != null && years.contains(_catYear)
                  ? _catYear
                  : years.first,
              decoration: filterDropdownFieldDecoration(
                style,
                AppLocalizations.of(context)!.modelYear,
              ),
              items: years
                  .map(
                    (y) => DropdownMenuItem<int>(
                      value: y,
                      child: Text(_localizeDigitsGlobal(context, '$y')),
                    ),
                  )
                  .toList(),
              onChanged: (y) {
                if (y == null) return;
                setState(() => _catYear = y);
                _schedDsRefresh();
              },
            ),
          ],
          if (previewSummary != null) ...[
            const SizedBox(height: 12),
            Text(
              previewSummary,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: kFilterAccentColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context)!.youCanChangeTheseInStep2,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ] else if (canApply) ...[
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.specsAvailableForThisYear,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kFilterAccentColor,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canApply ? _applyCatalogSpecsToFlow : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kFilterAccentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    kFilterAccentColor.withValues(alpha: 0.35),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                AppLocalizations.of(context)!.applySpecs,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
