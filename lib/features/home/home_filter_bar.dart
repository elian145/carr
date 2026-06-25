part of 'home_flow.dart';

mixin _HomePageFilterBar on _HomePageFilterBarBrand {
  Widget _buildHomeVehicleFilterRow(BuildContext filterRowContext) {
        final isLightShell =
            Theme.of(filterRowContext).brightness ==
            Brightness.light;
        final dropdownMenuInk = isLightShell
            ? AppThemes.darkHomeShellBackground
            : Colors.white;
        const dropdownFieldInk = Colors.white;
        final dropdownMenuBg = isLightShell
            ? Colors.white
            : AppThemes.darkHomeShellBackground;
        return Row(
      children: [
        // Brand selector styled like a form field for symmetry
        Expanded(
          child: InkWell(
            onTap: () => _pickHomeBrand(filterRowContext),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                )!.brandLabel,
                labelStyle: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 
                  0.15,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
              child: Row(
                children: [
                  if (_homeSelectedBrands.length == 1)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(6),
                      ),
                      padding: EdgeInsets.all(2),
                      child: CachedNetworkImage(
                        imageUrl:
                            '${getApiBase()}/static/images/brands/${brandLogoFilenames[_homeSelectedBrands.first] ?? _homeSelectedBrands.first.toLowerCase().replaceAll(' ', '-')}.png',
                        placeholder: (context, url) =>
                            SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                            ),
                        errorWidget:
                            (
                              context,
                              url,
                              error,
                            ) => Icon(
                              Icons.directions_car,
                              size: 16,
                              color: Color(
                                0xFFFF6B00,
                              ),
                            ),
                        fit: BoxFit.contain,
                      ),
                    )
                  else if (_homeSelectedBrands.isNotEmpty)
                    Icon(
                      Icons.layers_outlined,
                      size: 20,
                      color: Color(0xFFFF6B00),
                    )
                  else
                    Icon(
                      Icons.directions_car,
                      size: 20,
                      color: Color(0xFFFF6B00),
                    ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _homeBrandFilterLabel(filterRowContext),
                      style: GoogleFonts.orbitron(
                        fontSize: 14,
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
        SizedBox(width: 6),
        // Model Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            dropdownColor: dropdownMenuBg,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              color: dropdownMenuInk,
              fontWeight: FontWeight.bold,
            ),
            selectedItemBuilder: (context) => [
              Text(
                AppLocalizations.of(context)!.any,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.orbitron(
                  fontSize: 14,
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
                      fontSize: 14,
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
                            models[_homeSingleSelectedBrand] !=
                                null &&
                            models[_homeSingleSelectedBrand]!
                                .contains(
                                  selectedModel,
                                )))
                ? selectedModel
                : null,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(
                context,
              )!.modelLabel,
              labelStyle: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 
                0.15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 6,
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
                    color: isLightShell
                        ? const Color(0xFF757575)
                        : Colors.grey,
                    fontSize: 14,
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
                        fontSize: 14,
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
                selectedModel = value == ''
                    ? null
                    : value;
                selectedTrim = null;
                clearFiltersOnVehicleChange();
              });
              onFilterChanged();
            },
          ),
        ),
        SizedBox(width: 6),
        // Trim Dropdown
        Expanded(
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            dropdownColor: dropdownMenuBg,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              color: dropdownMenuInk,
              fontWeight: FontWeight.bold,
            ),
            selectedItemBuilder: (context) => [
              Text(
                AppLocalizations.of(context)!.any,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.orbitron(
                  fontSize: 14,
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
                          fontSize: 14,
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
              labelText:
                  AppLocalizations.of(context)!.trimLabel,
              labelStyle: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
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
                    color: isLightShell
                        ? const Color(0xFF757575)
                        : Colors.grey,
                    fontSize: 14,
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
                            fontSize: 14,
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
