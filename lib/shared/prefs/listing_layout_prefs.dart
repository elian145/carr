import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/debug/app_log.dart';

/// Global preference for listing layout.
///
/// - `2` = grid (2 columns)
/// - `1` = list (1 column / horizontal card)
/// - `3` = TikTok-style vertical scroll on card tap
class ListingLayoutPrefs {
  static const String _key = 'listing_columns_v1';

  static final ValueNotifier<int> columns = ValueNotifier<int>(2);

  /// Whether the current mode is TikTok-style vertical scroll.
  static bool get isTikTokMode => columns.value == 3;

  static int _sanitize(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '');
    if (n == 1 || n == 3) return n!;
    return 2;
  }

  static Future<int> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = _sanitize(sp.getInt(_key) ?? 2);
      columns.value = v;
      return v;
    } catch (e, st) { logNonFatal(e, st); 
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
    } catch (e, st) { logNonFatal(e, st); }
  }

  /// Grid cell aspect ratio (width / height) — matches Home feed so cards do not overflow.
  static double gridChildAspectRatio(int listingColumns) {
    if (listingColumns == 1) return 2.78;
    return Platform.isIOS ? 0.66 : 0.61;
  }
}

