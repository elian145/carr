import 'package:flutter/material.dart';

import '../../data/car_name_translations.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import 'brand_logo_image.dart';
import 'filter_card_sections.dart';

const double _brandRowHeight = 92;
const double _brandTileWidth = 72;
const double _brandGridSpacing = 10;
const int _brandExpandedVisibleRows = 4;

int _brandGridCrossAxisCount(double maxWidth) {
  return ((maxWidth + _brandGridSpacing) /
          (_brandTileWidth + _brandGridSpacing))
      .floor()
      .clamp(3, 8);
}

class FilterMakeSection extends StatelessWidget {
  const FilterMakeSection({
    super.key,
    required this.brands,
    required this.selectedBrand,
    required this.onBrandSelected,
    required this.brandsExpanded,
    required this.onToggleBrandsExpanded,
    required this.models,
    this.selectedModel,
    this.onModelSelected,
    this.trimList = const [],
    this.selectedTrim,
    this.onTrimSelected,
    this.featuredBrands,
    this.brandError = false,
    this.modelError = false,
    this.trimError = false,
    this.requiredFields = true,
    this.allowCustomModel = false,
    this.allowCustomTrim = false,
    this.isModelManualInput = false,
    this.isTrimManualInput = false,
    this.modelManualController,
    this.trimManualController,
    this.onToggleModelManual,
    this.onToggleTrimManual,
  });

  final List<String> brands;
  final String? selectedBrand;
  final ValueChanged<String?> onBrandSelected;
  final bool brandsExpanded;
  final VoidCallback onToggleBrandsExpanded;
  final Map<String, List<String>> models;
  final String? selectedModel;
  final ValueChanged<String?>? onModelSelected;
  final List<String> trimList;
  final String? selectedTrim;
  final ValueChanged<String?>? onTrimSelected;
  final List<String>? featuredBrands;
  final bool brandError;
  final bool modelError;
  final bool trimError;
  final bool requiredFields;
  final bool allowCustomModel;
  final bool allowCustomTrim;
  final bool isModelManualInput;
  final bool isTrimManualInput;
  final TextEditingController? modelManualController;
  final TextEditingController? trimManualController;
  final VoidCallback? onToggleModelManual;
  final VoidCallback? onToggleTrimManual;

  List<String> _featuredBrands() {
    if (featuredBrands != null && featuredBrands!.length >= 4) {
      return featuredBrands!.take(5).toList();
    }
    const defaultFeatured = [
      'Toyota',
      'Honda',
      'Ford',
      'Chevrolet',
      'BMW',
    ];
    final picked = defaultFeatured.where(brands.contains).toList();
    if (picked.length >= 4) return picked.take(5).toList();
    final extras = brands.where((b) => !picked.contains(b)).take(5 - picked.length);
    return [...picked, ...extras];
  }

  List<String> _collapsedBrands() {
    final featured = _featuredBrands();
    if (selectedBrand == null || selectedBrand!.isEmpty) return featured;
    final rest = featured.where((b) => b != selectedBrand).toList();
    return [selectedBrand!, ...rest];
  }

  String _brandSummary(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selectedBrand == null || selectedBrand!.isEmpty) {
      return loc.tapToSelect;
    }
    final localized = CarNameTranslations.getLocalizedBrand(context, selectedBrand);
    return localized.isNotEmpty ? localized : selectedBrand!;
  }

  String _modelSummary(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selectedModel == null || selectedModel!.isEmpty) {
      return loc.tapToSelect;
    }
    final localized = CarNameTranslations.getLocalizedModel(
      context,
      selectedBrand,
      selectedModel,
    );
    return localized.isNotEmpty ? localized : selectedModel!;
  }

  String _trimSummary(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selectedTrim == null || selectedTrim!.isEmpty) {
      return loc.tapToSelect;
    }
    return selectedTrim!;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final labelColor = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final collapsedBrands = _collapsedBrands();
    final hasBrand = selectedBrand != null && selectedBrand!.isNotEmpty;
    final hasModel = selectedModel != null && selectedModel!.trim().isNotEmpty;
    final modelList = hasBrand ? (models[selectedBrand!] ?? const <String>[]) : const <String>[];
    final showModel = hasBrand &&
        onModelSelected != null &&
        (modelList.isNotEmpty || allowCustomModel);
    final modelManual =
        allowCustomModel && (isModelManualInput || modelList.isEmpty);
    final showTrim = hasBrand &&
        hasModel &&
        onTrimSelected != null &&
        (trimList.isNotEmpty || allowCustomTrim);
    final trimManual =
        allowCustomTrim && (isTrimManualInput || trimList.isEmpty);
    final style = filterDialogStyle(context);

    return FilterCard(
      isError: brandError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterSectionHeader(
            title: loc.brandLabel,
            requiredField: requiredFields,
            valueSummary: _brandSummary(context),
            onSummaryTap: selectedBrand != null
                ? () => onBrandSelected(null)
                : null,
          ),
          const SizedBox(height: 14),
          if (brandsExpanded)
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = _brandGridCrossAxisCount(constraints.maxWidth);
                final expandedHeight = _brandRowHeight * _brandExpandedVisibleRows +
                    _brandGridSpacing * (_brandExpandedVisibleRows - 1);
                return SizedBox(
                  height: expandedHeight,
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: _brandGridSpacing,
                      crossAxisSpacing: _brandGridSpacing,
                      mainAxisExtent: _brandRowHeight,
                    ),
                    itemCount: brands.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _BrandActionTile(
                          labelColor: labelColor,
                          isLight: isLight,
                          icon: Icons.expand_less,
                          label: trLegacyText(
                            context,
                            'Less',
                            ar: 'أقل',
                            ku: 'کەمتر',
                          ),
                          onTap: onToggleBrandsExpanded,
                        );
                      }
                      final brand = brands[index - 1];
                      return _BrandTile(
                        brand: brand,
                        selected: selectedBrand == brand,
                        labelColor: labelColor,
                        onTap: () => onBrandSelected(
                          selectedBrand == brand ? null : brand,
                        ),
                      );
                    },
                  ),
                );
              },
            )
          else
            SizedBox(
              height: _brandRowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: collapsedBrands.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: _brandGridSpacing),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _BrandActionTile(
                      labelColor: labelColor,
                      isLight: isLight,
                      icon: Icons.more_horiz,
                      label: trLegacyText(
                        context,
                        'More',
                        ar: 'المزيد',
                        ku: 'زیاتر',
                      ),
                      onTap: onToggleBrandsExpanded,
                    );
                  }
                  final brand = collapsedBrands[index - 1];
                  return _BrandTile(
                    brand: brand,
                    selected: selectedBrand == brand,
                    labelColor: labelColor,
                    onTap: () => onBrandSelected(
                      selectedBrand == brand ? null : brand,
                    ),
                  );
                },
              ),
            ),
          if (showModel) ...[
            const SizedBox(height: 16),
            FilterSectionHeader(
              title: loc.modelLabel,
              requiredField: requiredFields,
              valueSummary: _modelSummary(context),
              onSummaryTap: selectedModel != null
                  ? () => onModelSelected!(null)
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: modelManual
                      ? TextFormField(
                          controller: modelManualController,
                          decoration: filterFieldDecoration(
                            style,
                            loc.modelLabel,
                            errorText:
                                modelError ? loc.pleaseSelectModel : null,
                          ).copyWith(
                            fillColor: isLight
                                ? Colors.white
                                : Colors.black.withValues(alpha: 0.2),
                          ),
                          style: TextStyle(color: style.onSurface),
                          textCapitalization: TextCapitalization.words,
                          onChanged: (value) {
                            onModelSelected!(
                              value.trim().isEmpty ? null : value.trim(),
                            );
                          },
                        )
                      : _ModelDropdown(
                          brand: selectedBrand!,
                          modelList: modelList,
                          selectedModel: selectedModel,
                          isError: modelError,
                          onChanged: onModelSelected!,
                        ),
                ),
                if (allowCustomModel && modelList.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onToggleModelManual,
                    icon: Icon(
                      modelManual ? Icons.list : Icons.edit,
                      color: kFilterAccentColor,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    tooltip: modelManual
                        ? trLegacyText(
                            context,
                            'Select from list',
                            ar: 'اختر من القائمة',
                            ku: 'لە لیستەکە هەڵبژێرە',
                          )
                        : loc.typeManually,
                  ),
                ],
              ],
            ),
          ],
          if (showTrim) ...[
            const SizedBox(height: 16),
            FilterSectionHeader(
              title: loc.trimLabel,
              requiredField: requiredFields,
              valueSummary: _trimSummary(context),
              onSummaryTap: selectedTrim != null
                  ? () => onTrimSelected!(null)
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: trimManual
                      ? TextFormField(
                          controller: trimManualController,
                          decoration: filterFieldDecoration(
                            style,
                            loc.trimLabel,
                            errorText: trimError ? loc.pleaseSelectTrim : null,
                          ).copyWith(
                            fillColor: isLight
                                ? Colors.white
                                : Colors.black.withValues(alpha: 0.2),
                          ),
                          style: TextStyle(color: style.onSurface),
                          textCapitalization: TextCapitalization.words,
                          onChanged: (value) {
                            onTrimSelected!(
                              value.trim().isEmpty ? null : value.trim(),
                            );
                          },
                        )
                      : _TrimDropdown(
                          trimList: trimList,
                          selectedTrim: selectedTrim,
                          isError: trimError,
                          onChanged: onTrimSelected!,
                        ),
                ),
                if (allowCustomTrim && trimList.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onToggleTrimManual,
                    icon: Icon(
                      trimManual ? Icons.list : Icons.edit,
                      color: kFilterAccentColor,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    tooltip: trimManual
                        ? trLegacyText(
                            context,
                            'Select from list',
                            ar: 'اختر من القائمة',
                            ku: 'لە لیستەکە هەڵبژێرە',
                          )
                        : loc.typeManually,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BrandActionTile extends StatelessWidget {
  const _BrandActionTile({
    required this.labelColor,
    required this.isLight,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color labelColor;
  final bool isLight;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _brandTileWidth,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.2),
                border: Border.all(color: const Color(0xFFE0E0E5)),
              ),
              child: Icon(icon, color: kFilterAccentColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile({
    required this.brand,
    required this.selected,
    required this.labelColor,
    required this.onTap,
  });

  final String brand;
  final bool selected;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display = CarNameTranslations.getLocalizedBrand(context, brand).isNotEmpty
        ? CarNameTranslations.getLocalizedBrand(context, brand)
        : brand;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _brandTileWidth,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kFilterAccentColor : const Color(0xFFE0E0E5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(8),
                child: BrandLogoImage(
                  brand: brand,
                  placeholderSize: 20,
                  errorIconSize: 22,
                  errorIconColor: kFilterAccentColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? kFilterAccentColor : labelColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.brand,
    required this.modelList,
    required this.selectedModel,
    required this.onChanged,
    this.isError = false,
  });

  final String brand;
  final List<String> modelList;
  final String? selectedModel;
  final ValueChanged<String?> onChanged;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final currentModel =
        selectedModel != null && modelList.contains(selectedModel)
            ? selectedModel
            : null;
    final style = filterDialogStyle(context);

    return FilterDropdownField(
      style: style,
      label: loc.modelLabel,
      value: currentModel,
      errorText: isError ? loc.pleaseSelectModel : null,
      narrowMenu: false,
      items: modelList.map((model) {
        final display = CarNameTranslations.getLocalizedModel(context, brand, model)
                .isNotEmpty
            ? CarNameTranslations.getLocalizedModel(context, brand, model)
            : model;
        return DropdownMenuItem<String>(
          value: model,
          child: Text(display, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      hint: Text(
        loc.tapToSelect,
        style: TextStyle(color: style.anyOrange, fontWeight: FontWeight.w600),
      ),
      onChanged: onChanged,
    );
  }
}

class _TrimDropdown extends StatelessWidget {
  const _TrimDropdown({
    required this.trimList,
    required this.selectedTrim,
    required this.onChanged,
    this.isError = false,
  });

  final List<String> trimList;
  final String? selectedTrim;
  final ValueChanged<String?> onChanged;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final currentTrim =
        selectedTrim != null && trimList.contains(selectedTrim) ? selectedTrim : null;
    final style = filterDialogStyle(context);

    return FilterDropdownField(
      style: style,
      label: loc.trimLabel,
      value: currentTrim,
      errorText: isError ? loc.pleaseSelectTrim : null,
      narrowMenu: false,
      items: trimList.map((trim) {
        return DropdownMenuItem<String>(
          value: trim,
          child: Text(trim, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      hint: Text(
        loc.tapToSelect,
        style: TextStyle(color: style.anyOrange, fontWeight: FontWeight.w600),
      ),
      onChanged: onChanged,
    );
  }
}
