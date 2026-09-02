import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/filter_card_sections.dart';

/// Sell flow: light shell field fill (matches search filter fields).
const Color kSellLightShellFieldFill = Colors.white;

Color sellFlowManualFieldFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.black.withValues(alpha: 0.2)
    : kSellLightShellFieldFill;

TextStyle sellFlowManualFieldLabelStyle(BuildContext context) =>
    TextStyle(
      color: filterDialogStyle(context).onSurface,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

TextStyle sellFlowManualFieldHintStyle(BuildContext context) =>
    TextStyle(
      color: filterDialogStyle(context).anyOrange,
      fontWeight: FontWeight.w600,
      fontSize: 18,
      height: 1.35,
      leadingDistribution: TextLeadingDistribution.even,
    );

TextStyle sellFlowManualFieldTextStyle(BuildContext context) =>
    TextStyle(
      color: filterDialogStyle(context).onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 18,
      height: 1.35,
      leadingDistribution: TextLeadingDistribution.even,
    );

Widget buildCurrencyIcon(String currency) {
  if (currency == 'IQD') {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.brandOrange,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Text(
          'IQD',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  return const Icon(Icons.attach_money, size: 24, color: AppColors.brandOrange);
}

Widget buildFancySelector(
  BuildContext context, {
  IconData? icon,
  required String label,
  required String? value,
  Widget? leading,
  bool isError = false,
  String? currency,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color accent = AppColors.brandOrange;
  final List<Color> bg = isDark
      ? [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.03)]
      : [kSellLightShellFieldFill, kSellLightShellFieldFill];
  final Color borderColor = isError
      ? Colors.redAccent
      : (isDark ? Colors.white12 : accent.withValues(alpha: 0.25));
  final Color labelColor = isError
      ? Colors.redAccent
      : (isDark ? Colors.white70 : Colors.grey[600]!);
  final loc = AppLocalizations.of(context)!;
  final bool valueShowsAny = value != null &&
      value.isNotEmpty &&
      (value == 'Any' ||
          value.trim().toLowerCase() == 'any' ||
          value == loc.any ||
          value == loc.anyOption);
  final bool isPlaceholder =
      value == null || value.isEmpty || value == loc.tapToSelect;
  final Color valueColor = isPlaceholder
      ? (isError ? Colors.redAccent : (isDark ? Colors.white38 : Colors.grey))
      : (isError
            ? Colors.redAccent
            : (valueShowsAny
                  ? accent
                  : (isDark ? Colors.white : Colors.grey[900]!)));
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: bg,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: (isError ? Colors.redAccent : accent).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        leading ??
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isError ? Colors.redAccent : accent)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: currency != null
                  ? Center(child: buildCurrencyIcon(currency))
                  : (icon != null
                        ? Icon(icon, color: isError ? Colors.redAccent : accent)
                        : const SizedBox.shrink()),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value == null || value.isEmpty
                    ? AppLocalizations.of(context)!.tapToSelect
                    : (value == 'Any'
                          ? AppLocalizations.of(context)!.anyOption
                          : value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
