part of 'sell_flow.dart';

mixin _SellStep2BuildMechanical on _SellStep2BuildAppearance {
  List<Widget> _sellStep2SpecsDropdownSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: AppLocalizations.of(context)!.specifications,
              valueSummary: '',
            ),
            const SizedBox(height: 12),
            FilterDropdownField(
              style: style,
              label: loc.seating,
              value: selectedSeating != null &&
                      getAvailableSeatings()
                          .where((s) => s != 'Any')
                          .contains(selectedSeating)
                  ? selectedSeating
                  : null,
              errorText: errSeating ? loc.pleaseSelectSeating : null,
              items: getAvailableSeatings()
                  .where((s) => s != 'Any')
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        '${_localizeDigitsGlobal(context, s)} ${AppLocalizations.of(context)!.seats}',
                      ),
                    ),
                  )
                  .toList(),
              hint: Text(
                loc.tapToSelect,
                style: TextStyle(
                  color: style.anyOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: (value) {
                setState(() => selectedSeating = value);
                _syncStep2DraftToParent();
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sellStep2BuildMechanicalSection() {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);

    return [
      FilterIconCardSection(
        title: loc.driveType,
        options: getAvailableDriveTypes(),
        selected: selectedDriveType,
        requiredField: true,
        isError: errDrive,
        scrollHorizontally: true,
        tileWidth: 88,
        tileImageWidth: 76,
        tileImageHeight: 76,
        tileImageBorderRadius: 8,
        iconForOption: filterDriveTypeIcon,
        imageAssetForOption: driveTypeImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() {
            selectedDriveType = value;
            _syncStep2ToOnlineVariant({'drv'});
          });
          _syncStep2DraftToParent();
        },
        onClear: selectedDriveType != null
            ? () {
                setState(() => selectedDriveType = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      FilterIconCardSection(
        title: loc.regionSpecsLabel,
        options: List<String>.from(kCarRegionSpecCodes),
        selected: selectedRegionSpecs,
        requiredField: true,
        isError: errRegionSpecs,
        scrollHorizontally: true,
        tileWidth: 80,
        tileImageWidth: 40,
        tileImageHeight: 28,
        tileImageFit: BoxFit.cover,
        tileImageBorderRadius: 4,
        iconForOption: filterRegionSpecIcon,
        imageAssetForOption: regionSpecFlagAsset,
        labelForOption: (ctx, o) => carRegionSpecDisplayLabelLocalized(ctx, o),
        onSelected: (value) {
          setState(() => selectedRegionSpecs = value?.trim().toLowerCase());
          _syncStep2DraftToParent();
        },
        onClear: selectedRegionSpecs != null
            ? () {
                setState(() => selectedRegionSpecs = null);
                _syncStep2DraftToParent();
              }
            : null,
      ),
      ..._sellStep2SpecsDropdownSection(),
      FilterCard(
        child: TextFormField(
          controller: _vinController,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: filterDialogStyle(context).onSurface),
          decoration: filterFieldDecoration(
            style,
            AppLocalizations.of(context)!.vinOptional,
          ).copyWith(
            hintText: 'e.g. 1HGBH41JXMN109186',
          ),
          onChanged: (value) {
            selectedVin = value.trim().isEmpty ? null : value.trim();
            _syncStep2DraftToParent();
          },
          validator: (v) {
            final trimmed = (v ?? '').trim();
            if (trimmed.isEmpty) return null;
            if (trimmed.length != 17) {
              return AppLocalizations.of(context)!.vinMustBe17Characters;
            }
            return null;
          },
        ),
      ),
    ];
  }
}
