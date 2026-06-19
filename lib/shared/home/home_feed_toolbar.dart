import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../prefs/listing_layout_prefs.dart';
import 'home_sort_api.dart';

/// Sort menu + grid/list/TikTok layout toggle for the home feed.
Widget buildHomeFeedToolbar({
  required BuildContext context,
  required String? selectedSortBy,
  required int listingColumns,
  required ValueChanged<String?> onSortSelected,
  required ValueChanged<int> onLayoutSelected,
}) {
  final loc = AppLocalizations.of(context)!;

  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        PopupMenuButton<String>(
          tooltip: loc.sortBy,
          icon: const Icon(Icons.sort, size: 20),
          onSelected: (value) {
            onSortSelected(value.isEmpty ? null : value);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: '',
              child: Text(loc.defaultSort),
            ),
            ...homeLocalizedSortOptions(context).skip(1).map(
                  (s) => PopupMenuItem(value: s, child: Text(s)),
                ),
          ],
        ),
        ToggleButtons(
          isSelected: [
            listingColumns == 1,
            listingColumns == 2,
            listingColumns == 3,
          ],
          onPressed: onLayoutSelected,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
          children: const [
            Icon(Icons.view_agenda, size: 18),
            Icon(Icons.grid_view, size: 18),
            Icon(Icons.swipe_vertical, size: 18),
          ],
        ),
      ],
    ),
  );
}

/// Rebuild when listing column preference changes.
Widget buildHomeFeedToolbarWithLayoutListener({
  required BuildContext context,
  required String? selectedSortBy,
  required ValueChanged<String?> onSortSelected,
  required ValueChanged<int> onLayoutSelected,
}) {
  return ValueListenableBuilder<int>(
    valueListenable: ListingLayoutPrefs.columns,
    builder: (context, cols, _) {
      return buildHomeFeedToolbar(
        context: context,
        selectedSortBy: selectedSortBy,
        listingColumns: cols,
        onSortSelected: onSortSelected,
        onLayoutSelected: (index) {
          final next = index == 0 ? 1 : (index == 1 ? 2 : 3);
          onLayoutSelected(next);
        },
      );
    },
  );
}
