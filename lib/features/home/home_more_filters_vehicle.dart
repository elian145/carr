part of 'home_flow.dart';

mixin _HomePageMoreFiltersVehicle on _HomePageFilterBar {
  void _openMoreFiltersBrandModelSearch(
    BuildContext context,
    void Function(void Function()) setStateDialog,
  ) {
    showHomeBrandModelSearchDialog(
      context: context,
      brands: homeBrands,
      models: models,
      onBrandSelected: (brand) {
        setState(() {
          selectedBrand = brand;
          selectedModel = null;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        setStateDialog(() {});
      },
      onModelSelected: (brand, model) {
        setState(() {
          selectedBrand = brand;
          selectedModel = model;
          selectedTrim = null;
          clearFiltersOnVehicleChange();
        });
        setStateDialog(() {});
      },
    );
  }

  InputDecoration _moreFiltersFilterFieldDecoration(
    MoreFiltersDialogStyle style,
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: style.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      filled: true,
      fillColor: style.fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _moreFiltersRangeModeToggle({
    required MoreFiltersDialogStyle style,
    required bool isDropdown,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        isDropdown ? Icons.edit : Icons.list,
        color: const Color(0xFFFF6B00),
      ),
      style: IconButton.styleFrom(
        backgroundColor: style.fieldFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _moreFiltersRangeSectionHeader({
    required String title,
    required MoreFiltersDialogStyle style,
    required Widget toggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: style.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        toggle,
      ],
    );
  }

  Widget _moreFiltersMinMaxRow({
    required Widget minField,
    required Widget maxField,
    double gap = 8,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: minField),
        SizedBox(width: gap),
        Expanded(child: maxField),
      ],
    );
  }

  InputDecoration _moreFiltersVehicleFieldDecoration(
    BuildContext context,
    MoreFiltersDialogStyle style,
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: style.onSurface,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: style.fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  List<Widget> _moreFiltersVehicleWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final dropdownMenuBg =
        isLightShell ? Colors.white : AppThemes.darkHomeShellBackground;
    final dropdownInk = style.onSurface;
    final anyLabelStyle = TextStyle(color: style.anyOrange);

    String brandLabel() {
      if (selectedBrand == null || selectedBrand!.isEmpty) {
        return loc.any;
      }
      final localized =
          CarNameTranslations.getLocalizedBrand(context, selectedBrand);
      return localized.isNotEmpty ? localized : selectedBrand!;
    }

    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          loc.homeSearchHeading,
          style: TextStyle(
            color: style.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              _openMoreFiltersBrandModelSearch(context, setStateDialog),
          style: OutlinedButton.styleFrom(
            foregroundColor: style.anyOrange,
            side: BorderSide(color: style.anyOrange),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.search, size: 20),
          label: Text(
            _trLegacyText(
              context,
              'Search brands & models',
              ar: 'بحث عن الماركات والموديلات',
              ku: 'گەڕان بەدوای براند و مۆدێل',
            ),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(height: 12),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openMoreFiltersBrandModelSearch(context, setStateDialog),
        child: InputDecorator(
          decoration: _moreFiltersVehicleFieldDecoration(
            context,
            style,
            loc.brandLabel,
          ),
          child: Row(
            children: [
              if (selectedBrand != null && selectedBrand!.isNotEmpty)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CachedNetworkImage(
                    imageUrl:
                        '${getApiBase()}/static/images/brands/${brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')}.png',
                    placeholder: (context, url) => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Icon(
                      Icons.directions_car,
                      size: 16,
                      color: style.anyOrange,
                    ),
                    fit: BoxFit.contain,
                  ),
                )
              else
                Icon(Icons.directions_car, size: 20, color: style.anyOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  brandLabel(),
                  style: TextStyle(
                    color: dropdownInk,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        dropdownColor: dropdownMenuBg,
        style: TextStyle(color: dropdownInk, fontWeight: FontWeight.w600),
        value: selectedModel != null &&
                selectedModel!.isNotEmpty &&
                selectedBrand != null &&
                models[selectedBrand] != null &&
                models[selectedBrand]!.contains(selectedModel)
            ? selectedModel
            : '',
        decoration: _moreFiltersVehicleFieldDecoration(
          context,
          style,
          loc.modelLabel,
        ),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(loc.any, style: anyLabelStyle),
          ),
          if (selectedBrand != null && models[selectedBrand] != null)
            ...models[selectedBrand]!.map(
              (model) => DropdownMenuItem(
                value: model,
                child: Text(
                  CarNameTranslations.getLocalizedModel(
                            context,
                            selectedBrand,
                            model,
                          ).isNotEmpty
                      ? CarNameTranslations.getLocalizedModel(
                          context,
                          selectedBrand,
                          model,
                        )
                      : model,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        onChanged: selectedBrand == null
            ? null
            : (value) {
                setState(() {
                  selectedModel = value == null || value.isEmpty ? null : value;
                  selectedTrim = null;
                  clearFiltersOnVehicleChange();
                });
                setStateDialog(() {});
              },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        dropdownColor: dropdownMenuBg,
        style: TextStyle(color: dropdownInk, fontWeight: FontWeight.w600),
        value: selectedTrim != null &&
                selectedTrim!.isNotEmpty &&
                selectedBrand != null &&
                selectedModel != null &&
                trimsByBrandModel[selectedBrand] != null &&
                trimsByBrandModel[selectedBrand]![selectedModel] != null &&
                trimsByBrandModel[selectedBrand]![selectedModel]!
                    .contains(selectedTrim)
            ? selectedTrim
            : '',
        decoration: _moreFiltersVehicleFieldDecoration(
          context,
          style,
          loc.trimLabel,
        ),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(loc.any, style: anyLabelStyle),
          ),
          if (selectedBrand != null &&
              selectedModel != null &&
              trimsByBrandModel[selectedBrand] != null &&
              trimsByBrandModel[selectedBrand]![selectedModel] != null)
            ...trimsByBrandModel[selectedBrand]![selectedModel]!.map(
              (trim) => DropdownMenuItem(
                value: trim,
                child: Text(trim, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
        onChanged: selectedBrand == null || selectedModel == null
            ? null
            : (value) {
                setState(() {
                  selectedTrim = value == null || value.isEmpty ? null : value;
                  clearFiltersOnVehicleChange();
                });
                setStateDialog(() {});
              },
      ),
      const SizedBox(height: 20),
    ];
  }
}
