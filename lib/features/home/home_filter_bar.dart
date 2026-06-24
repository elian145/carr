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
                  if (selectedBrand != null &&
                      selectedBrand!.isNotEmpty)
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
                            '${getApiBase()}/static/images/brands/${brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')}.png',
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
                  else
                    Icon(
                      Icons.directions_car,
                      size: 20,
                      color: Color(0xFFFF6B00),
                    ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      selectedBrand == null ||
                              selectedBrand!.isEmpty
                          ? AppLocalizations.of(
                              context,
                            )!.any
                          : (CarNameTranslations.getLocalizedBrand(
                                  context,
                                  selectedBrand,
                                ).isNotEmpty
                                ? CarNameTranslations.getLocalizedBrand(
                                    context,
                                    selectedBrand,
                                  )
                                : selectedBrand!),
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
              if (selectedBrand != null &&
                  models[selectedBrand!] != null)
                ...models[selectedBrand!]!.map(
                  (m) => Text(
                    CarNameTranslations.getLocalizedModel(
                          context,
                          selectedBrand,
                          m,
                        ).isNotEmpty
                        ? CarNameTranslations.getLocalizedModel(
                            context,
                            selectedBrand,
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
                        (selectedBrand != null &&
                            models[selectedBrand] !=
                                null &&
                            models[selectedBrand]!
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
              if (selectedBrand != null &&
                  models[selectedBrand!] != null)
                ...models[selectedBrand!]!.map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      CarNameTranslations.getLocalizedModel(
                            context,
                            selectedBrand,
                            m,
                          ).isNotEmpty
                          ? CarNameTranslations.getLocalizedModel(
                              context,
                              selectedBrand,
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
            onChanged: (value) {
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
              if (selectedBrand != null &&
                  selectedModel != null &&
                  trimsByBrandModel[selectedBrand] != null &&
                  trimsByBrandModel[selectedBrand]![selectedModel] !=
                      null)
                ...trimsByBrandModel[selectedBrand]![selectedModel]!
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
                        (selectedBrand != null &&
                            selectedModel != null &&
                            trimsByBrandModel[selectedBrand] !=
                                null &&
                            trimsByBrandModel[selectedBrand]![selectedModel] !=
                                null &&
                            trimsByBrandModel[selectedBrand]![selectedModel]!
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
              if (selectedBrand != null &&
                  selectedModel != null &&
                  trimsByBrandModel[selectedBrand] != null &&
                  trimsByBrandModel[selectedBrand]![selectedModel] !=
                      null)
                ...trimsByBrandModel[selectedBrand]![selectedModel]!
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
            onChanged: (value) {
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
