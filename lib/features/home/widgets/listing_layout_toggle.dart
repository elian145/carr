import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

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
      padding: EdgeInsets.zero,
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
            tooltip: AppLocalizations.of(context)!.homeLayoutList,
            onTap: () => onChanged(1),
          ),
          _Segment(
            icon: Icons.grid_view_rounded,
            selected: columns == 2,
            tooltip: AppLocalizations.of(context)!.homeLayoutGrid,
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

    // F-24: one labelled, selectable button for screen readers (the tooltip
    // text is the label; the tooltip itself is excluded to avoid a double
    // announcement) with a 48x48 touch target around the unchanged 38x32 pill.
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      onTap: selected ? null : onTap,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
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
                child: Icon(
                  icon,
                  size: 18,
                  // F-24: unselected icons were ~2.4:1 on the toggle track
                  // (below the 3:1 non-text minimum).
                  color: selected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant.withValues(
                          alpha: isDark ? 0.9 : 0.85,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
