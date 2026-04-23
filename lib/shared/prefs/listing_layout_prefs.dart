import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global preference for listing layout.
///
/// - `2` = grid (2 columns)
/// - `1` = list (1 column / horizontal card)
class ListingLayoutPrefs {
  static const String _key = 'listing_columns_v1';

  static final ValueNotifier<int> columns = ValueNotifier<int>(2);

  static int _sanitize(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '');
    return (n == 1) ? 1 : 2;
  }

  static Future<int> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = _sanitize(sp.getInt(_key) ?? 2);
      columns.value = v;
      return v;
    } catch (_) {
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
    } catch (_) {}
  }
}

