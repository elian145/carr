part of 'home_flow.dart';

mixin _HomePageMoreFiltersVehicle on _HomePageFilterBar {
  void _openMoreFiltersBrandModelSearch(
    BuildContext context,
    void Function(void Function()) setStateDialog,
  ) {
    _focusSearchFiltersKeywordField();
    setStateDialog(() {});
  }

  double _moreFiltersDropdownMenuMaxHeight(BuildContext context) =>
      filterDropdownMenuMaxHeight(context);

  InputDecoration _moreFiltersColorMatchedFieldDecoration(
    MoreFiltersDialogStyle style,
    String label, {
    bool compactLabel = false,
  }) =>
      filterDropdownFieldDecoration(
        style,
        label,
        compactLabel: compactLabel,
      );

  Widget _moreFiltersRangeModeToggle({
    required BuildContext context,
    required MoreFiltersDialogStyle style,
    required bool isDropdown,
    required VoidCallback onPressed,
  }) {
    final loc = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: isDropdown ? loc.typeManually : loc.selectFromList,
      onPressed: onPressed,
      icon: Icon(
        isDropdown ? Icons.edit : Icons.list,
        color: AppColors.brandOrange,
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
    Widget? toggle,
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
        if (toggle != null) toggle,
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

  Widget _moreFiltersDropdownField({
    required BuildContext context,
    required MoreFiltersDialogStyle style,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    bool narrowMenu = false,
  }) {
    return FilterDropdownField(
      style: style,
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
      narrowMenu: narrowMenu,
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
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: style.onSurface,
        fontSize: 17,
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
      return _homeBrandFilterLabel(context);
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
            AppLocalizations.of(context)!.searchBrandsModels,
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
              if (_homeSelectedBrand != null)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: BrandLogoImage(
                    brand: _homeSelectedBrand!,
                    placeholderSize: 16,
                    errorIconSize: 16,
                    errorIconColor: style.anyOrange,
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
        menuMaxHeight: _moreFiltersDropdownMenuMaxHeight(context),
        dropdownColor: dropdownMenuBg,
        style: TextStyle(color: dropdownInk, fontWeight: FontWeight.w600),
        value: selectedModel != null &&
                selectedModel!.isNotEmpty &&
                _homeSingleSelectedBrand != null &&
                models[_homeSingleSelectedBrand] != null &&
                models[_homeSingleSelectedBrand]!.contains(selectedModel)
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
          if (_homeSingleSelectedBrand != null &&
              models[_homeSingleSelectedBrand] != null)
            ...models[_homeSingleSelectedBrand]!.map(
              (model) => DropdownMenuItem(
                value: model,
                child: Text(
                  CarNameTranslations.getLocalizedModel(
                            context,
                            _homeSingleSelectedBrand,
                            model,
                          ).isNotEmpty
                      ? CarNameTranslations.getLocalizedModel(
                          context,
                          _homeSingleSelectedBrand,
                          model,
                        )
                      : model,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        onChanged: _homeSingleSelectedBrand == null
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
        menuMaxHeight: _moreFiltersDropdownMenuMaxHeight(context),
        dropdownColor: dropdownMenuBg,
        style: TextStyle(color: dropdownInk, fontWeight: FontWeight.w600),
        value: selectedTrim != null &&
                selectedTrim!.isNotEmpty &&
                _homeSingleSelectedBrand != null &&
                selectedModel != null &&
                trimsByBrandModel[_homeSingleSelectedBrand] != null &&
                trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel] !=
                    null &&
                trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel]!
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
          if (_homeSingleSelectedBrand != null &&
              selectedModel != null &&
              trimsByBrandModel[_homeSingleSelectedBrand] != null &&
              trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel] !=
                  null)
            ...trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel]!.map(
              (trim) => DropdownMenuItem(
                value: trim,
                child: Text(trim, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
        onChanged: _homeSingleSelectedBrand == null || selectedModel == null
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
