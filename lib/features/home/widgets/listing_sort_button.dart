import 'package:flutter/material.dart';

/// Compact sort trigger styled to match [ListingLayoutToggle].
class ListingSortButton extends StatelessWidget {
  const ListingSortButton({
    super.key,
    required this.tooltip,
    required this.active,
    required this.itemBuilder,
    required this.onSelected,
  });

  final String tooltip;
  final bool active;
  final PopupMenuItemBuilder<String> itemBuilder;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isDark
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
              : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.7),
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 38,
          height: 32,
          decoration: BoxDecoration(
            color: active ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.sort_rounded,
            size: 18,
            color: active
                ? scheme.onPrimary
                : scheme.onSurfaceVariant.withValues(
                    alpha: isDark ? 0.75 : 0.55,
                  ),
          ),
        ),
      ),
    );
  }
}
