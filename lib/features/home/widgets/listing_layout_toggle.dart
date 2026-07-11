import 'package:flutter/material.dart';

/// Compact list/grid layout switcher for the home feed.
class ListingLayoutToggle extends StatelessWidget {
  const ListingLayoutToggle({
    super.key,
    required this.columns,
    required this.onChanged,
  });

  /// `1` = list, `2` = grid.
  final int columns;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.view_agenda_rounded,
            selected: columns == 1,
            tooltip: 'List',
            onTap: () => onChanged(1),
          ),
          _Segment(
            icon: Icons.grid_view_rounded,
            selected: columns == 2,
            tooltip: 'Grid',
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 38,
        height: 32,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(9),
            child: Icon(
              icon,
              size: 18,
              color: selected
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant.withValues(
                      alpha: isDark ? 0.75 : 0.55,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
