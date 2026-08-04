import 'package:flutter/material.dart';

import '../../features/home/home_filter_chip_style.dart';
import '../../l10n/app_localizations.dart';
import 'filter_card_sections.dart';

class FilterColorField extends StatelessWidget {
  const FilterColorField({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
    required this.labelForColor,
    this.isError = false,
    this.requiredField = false,
    this.onClear,
  });

  final List<String> colors;
  final String? selectedColor;
  final ValueChanged<String?> onColorSelected;
  final String Function(BuildContext, String) labelForColor;
  final bool isError;
  final bool requiredField;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final style = filterDialogStyle(context);
    final display = selectedColor == null || selectedColor!.isEmpty
        ? loc.tapToSelect
        : labelForColor(context, selectedColor!);

    return FilterCard(
      isError: isError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterSectionHeader(
            title: loc.colorLabel,
            requiredField: requiredField,
            valueSummary: display,
            onSummaryTap: onClear,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey<String?>(selectedColor),
            readOnly: true,
            style: TextStyle(
              color: selectedColor != null && selectedColor!.isNotEmpty
                  ? style.onSurface
                  : style.anyOrange,
              fontWeight: FontWeight.w600,
            ),
            initialValue: display,
            decoration: filterFieldDecoration(
              style,
              loc.colorLabel,
              errorText: isError ? loc.pleaseSelectColor : null,
              suffixIcon: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selectedColor != null
                      ? homeFilterNamedColor(selectedColor!)
                      : Colors.grey,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
              ),
            ),
            onTap: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (dlgContext) => _ColorPickerDialog(
                  colors: colors,
                  labelForColor: labelForColor,
                ),
              );
              if (choice != null) {
                onColorSelected(choice);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({
    required this.colors,
    required this.labelForColor,
  });

  final List<String> colors;
  final String Function(BuildContext, String) labelForColor;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pickerBg = isLight ? Colors.white : Colors.grey.shade900;
    final onPicker = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final borderSubtle = isLight ? Colors.black26 : Colors.white24;
    final cellFill = isLight ? Colors.grey.shade200 : Colors.black.withValues(alpha: 0.15);

    return Dialog(
      backgroundColor: pickerBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.selectColor,
                    style: TextStyle(
                      color: kFilterAccentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.close,
                    icon: Icon(Icons.close, color: onPicker),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: colors.length,
                  itemBuilder: (context, index) {
                    final colorName = colors[index];
                    final colorValue = homeFilterNamedColor(colorName);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, colorName),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cellFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderSubtle),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colorValue,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderSubtle, width: 2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              labelForColor(context, colorName),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                color: onPicker,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
