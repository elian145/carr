part of 'home_flow.dart';

mixin _HomePageFilterBar on _HomePageFilterBarBrand {
  Widget _buildHomeVehicleFilterRow(BuildContext filterRowContext) {
    final isLightShell =
        Theme.of(filterRowContext).brightness == Brightness.light;
    final dropdownMenuInk = isLightShell
        ? AppThemes.darkHomeShellBackground
        : Colors.white;
    const dropdownFieldInk = Colors.white;
    final dropdownMenuBg = isLightShell
        ? Colors.white
        : AppThemes.darkHomeShellBackground;
    final compact = AppResponsive.isCompactPhone(filterRowContext);
    final labelFontSize = compact ? 12.0 : 15.0;
    final valueFontSize = compact ? 11.0 : 14.0;
    final fieldGap = compact ? 4.0 : 6.0;
    return Row(
      children: [
        // Brand selector styled like a form field for symmetry
        Expanded(
          child: InkWell(
            onTap: () => _pickHomeBrand(filterRowContext),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.brandLabel,
                labelStyle: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.bold,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 10,
                  vertical: 12,
                ),
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
                      padding: EdgeInsets.all(2),
                      child: BrandLogoImage(
                        brand: _homeSelectedBrand!,
                        placeholderSize: 16,
                        errorIconSize: 16,
                      ),
                    )
                  else
                    Icon(
                      Icons.directions_car,
                      size: 20,
                      color: AppColors.brandOrange,
                    ),
                  SizedBox(width: fieldGap),
                  Expanded(
                    child: Text(
                      _homeBrandFilterLabel(filterRowContext),
                      style: GoogleFonts.orbitron(
                        fontSize: valueFontSize,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: fieldGap),
        // Model Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            dropdownColor: dropdownMenuBg,
            style: GoogleFonts.orbitron(
              fontSize: valueFontSize,
              color: dropdownMenuInk,
              fontWeight: FontWeight.bold,
            ),
            selectedItemBuilder: (context) => [
              Text(
                AppLocalizations.of(context)!.any,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.orbitron(
                  fontSize: valueFontSize,
                  color: dropdownFieldInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_homeSingleSelectedBrand != null &&
                  models[_homeSingleSelectedBrand!] != null)
                ...models[_homeSingleSelectedBrand!]!.map(
                  (m) => Text(
                    CarNameTranslations.getLocalizedModel(
                          context,
                          _homeSingleSelectedBrand,
                          m,
                        ).isNotEmpty
                        ? CarNameTranslations.getLocalizedModel(
                            context,
                            _homeSingleSelectedBrand,
                            m,
                          )
                        : m,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.orbitron(
                      fontSize: valueFontSize,
                      color: dropdownFieldInk,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
            initialValue:
                selectedModel != null &&
                    (selectedModel!.isEmpty ||
                        (_homeSingleSelectedBrand != null &&
                            models[_homeSingleSelectedBrand] != null &&
                            models[_homeSingleSelectedBrand]!.contains(
                              selectedModel,
                            )))
                ? selectedModel
                : null,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.modelLabel,
              labelStyle: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: labelFontSize,
                fontWeight: FontWeight.bold,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: 6,
              ),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  AppLocalizations.of(context)!.any,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.orbitron(
                    color: isLightShell ? const Color(0xFF757575) : Colors.grey,
                    fontSize: valueFontSize,
                  ),
                ),
              ),
              if (_homeSingleSelectedBrand != null &&
                  models[_homeSingleSelectedBrand!] != null)
                ...models[_homeSingleSelectedBrand!]!.map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      CarNameTranslations.getLocalizedModel(
                            context,
                            _homeSingleSelectedBrand,
                            m,
                          ).isNotEmpty
                          ? CarNameTranslations.getLocalizedModel(
                              context,
                              _homeSingleSelectedBrand,
                              m,
                            )
                          : m,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.orbitron(
                        fontSize: valueFontSize,
                        color: dropdownMenuInk,
                      ),
                    ),
                  ),
                ),
            ],
            onChanged: _homeSingleSelectedBrand == null
                ? null
                : (value) {
                    setState(() {
                      selectedModel = value == '' ? null : value;
                      selectedTrim = null;
                      clearFiltersOnVehicleChange();
                    });
                    onFilterChanged();
                  },
          ),
        ),
        SizedBox(width: fieldGap),
        // Trim Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            dropdownColor: dropdownMenuBg,
            style: GoogleFonts.orbitron(
              fontSize: valueFontSize,
              color: dropdownMenuInk,
              fontWeight: FontWeight.bold,
            ),
            selectedItemBuilder: (context) => [
              Text(
                AppLocalizations.of(context)!.any,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.orbitron(
                  fontSize: valueFontSize,
                  color: dropdownFieldInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_homeSingleSelectedBrand != null &&
                  selectedModel != null &&
                  trimsByBrandModel[_homeSingleSelectedBrand] != null &&
                  trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel] !=
                      null)
                ...trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel]!
                    .map(
                      (t) => Text(
                        t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.orbitron(
                          fontSize: valueFontSize,
                          color: dropdownFieldInk,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ],
            initialValue:
                selectedTrim != null &&
                    (selectedTrim!.isEmpty ||
                        (_homeSingleSelectedBrand != null &&
                            selectedModel != null &&
                            trimsByBrandModel[_homeSingleSelectedBrand] !=
                                null &&
                            trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel] !=
                                null &&
                            trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel]!
                                .contains(selectedTrim)))
                ? selectedTrim
                : null,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.trimLabel,
              labelStyle: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: labelFontSize,
                fontWeight: FontWeight.bold,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: 6,
              ),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  AppLocalizations.of(context)!.any,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.orbitron(
                    color: isLightShell ? const Color(0xFF757575) : Colors.grey,
                    fontSize: valueFontSize,
                  ),
                ),
              ),
              if (_homeSingleSelectedBrand != null &&
                  selectedModel != null &&
                  trimsByBrandModel[_homeSingleSelectedBrand] != null &&
                  trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel] !=
                      null)
                ...trimsByBrandModel[_homeSingleSelectedBrand]![selectedModel]!
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          t,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.orbitron(
                            fontSize: valueFontSize,
                            color: dropdownMenuInk,
                          ),
                        ),
                      ),
                    ),
            ],
            onChanged: _homeSingleSelectedBrand == null || selectedModel == null
                ? null
                : (value) {
                    setState(() {
                      selectedTrim = value == '' ? null : value;
                      clearFiltersOnVehicleChange();
                    });
                    onFilterChanged();
                  },
          ),
        ),
      ],
    );
  }
}
