import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/debug/app_log.dart';

/// Global preference for listing layout.
///
/// - `2` = grid (2 columns)
/// - `1` = list (1 column / horizontal card)
class ListingLayoutPrefs {
  static const String _key = 'listing_columns_v1';

  static final ValueNotifier<int> columns = ValueNotifier<int>(2);

  static int _sanitize(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '');
    if (n == 1) return n!;
    return 2;
  }

  static Future<int> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = _sanitize(sp.getInt(_key) ?? 2);
      columns.value = v;
      return v;
    } catch (e, st) {
      logNonFatal(e, st);
      columns.value = 2;
      return 2;
    }
  }

  static Future<void> setColumns(int value) async {
    final v = _sanitize(value);
    columns.value = v;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_key, v);
    } catch (e, st) {
      logNonFatal(e, st);
    }
  }

  /// Grid cell aspect ratio (width / height) — matches Home feed so cards do not overflow.
  static double gridChildAspectRatio(int listingColumns) {
    if (listingColumns == 1) return 2.55;
    return 0.66;
  }

  /// Resolves list vs grid, then expands grid columns on tablet / landscape (UI-04).
  ///
  /// - list (`requestedColumns == 1`) → always 1
  /// - grid: 2 on phones, 3 from ~720, 4 from ~1000
  static int effectiveColumnsForWidth(int requestedColumns, double width) {
    if (requestedColumns == 1) {
      return requestedColumns;
    }
    if (width < 720) return 2;
    if (width < 1000) return 3;
    return 4;
  }

  static double gridChildAspectRatioForWidth(int listingColumns, double width) {
    if (listingColumns == 1) {
      // Give the four information rows comfortable vertical spacing.
      if (width < 320) return 2.20;
      if (width < 340) return 2.30;
      if (width < 380) return 2.45;
      return 2.55;
    }
    if (listingColumns >= 3) {
      // Slightly taller tiles so title/price stay readable in narrower columns.
      return width >= 1000 ? 0.72 : 0.70;
    }
    // Taller cells → more image area; text block sizes are fixed in the card.
    if (width < 320) return 0.59;
    if (width < 380) return 0.61;
    if (width >= 420) return 0.64;
    return 0.62;
  }
}
