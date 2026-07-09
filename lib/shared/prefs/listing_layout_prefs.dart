import 'dart:io' show Platform;

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
    if (listingColumns == 1) return 2.82;
    return Platform.isIOS ? 0.67 : 0.63;
  }

  static int effectiveColumnsForWidth(int requestedColumns, double width) {
    if (requestedColumns == 1) {
      return requestedColumns;
    }
    return width < 340 ? 1 : 2;
  }

  static double gridChildAspectRatioForWidth(int listingColumns, double width) {
    if (listingColumns == 1) {
      if (width < 340) return 2.48;
      if (width < 380) return 2.68;
      return 2.82;
    }
    if (width < 340) return 2.55;
    if (width < 380) return Platform.isIOS ? 0.64 : 0.60;
    return gridChildAspectRatio(listingColumns);
  }
}
