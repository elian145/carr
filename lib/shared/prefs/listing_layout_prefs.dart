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

  /// Height (dp) of the text block under the photo in a grid listing card at
  /// text scale 1.0 (regular phones).
  static const double gridCardTextBlockHeight = 150;

  /// Same block on compact phones (< 360 dp wide), which use smaller chips.
  static const double gridCardCompactTextBlockHeight = 136;

  /// How many dp the text block must grow for every +1.0 of system text scale.
  ///
  /// Derived from the card's real layout (global_listing_card_inner_text.dart):
  /// two title lines (2 x 15 x 1.28 = 38.4) + two chip rows (2 x 13) + price
  /// footer (28) = 92.4 dp per 1.0 of text scale; the card's remaining
  /// heights are fixed paddings/gaps. The chip rows and the footer sit in
  /// fixed-height slots, so this is exact for every listing (long trims that
  /// scale their chips down no longer change it). Rounded up to 93 so a font
  /// whose line box rounds up never clips the footer.
  ///
  /// This used to be 150 (the 1.0x block height), i.e. the cell grew ~58 dp per
  /// scale step more than the content, and all of it ended up as empty space
  /// between the year/mileage chips and the city/price footer.
  static const double gridCardTextBlockGrowthPerScale = 93;

  /// Compact phones (< 360 dp) use 11 dp chips: 38.4 + 2 x 11 + footer
  /// (26..28) = 86.4..88.4 dp per 1.0 of text scale, rounded up to 89.
  static const double gridCardCompactTextBlockGrowthPerScale = 89;

  /// Mirrors `AppResponsive.compactPhoneWidth` (not imported: responsive.dart
  /// already depends on this file).
  static const double _compactPhoneWidth = 360;

  static double _textBlockGrowth({required bool compact}) => compact
      ? gridCardCompactTextBlockGrowthPerScale
      : gridCardTextBlockGrowthPerScale;

  /// The orange price badge (and the footer row it sits in) stops following
  /// the system text size at this scale: the price is already bold 15 sp text
  /// in a solid pill, and an unbounded pill doubled in height (52 dp at 2.0x)
  /// while the text inside could not grow with it. Title, chips and city keep
  /// following the system text size.
  static const double priceBadgeMaxTextScale = 1.3;

  /// Height of the price footer row per 1.0 of (uncapped) text scale:
  /// `(26 + 2) * scale` in `_listingPriceBadgeStyle`.
  static const double priceFooterHeightPerScale = 28;

  /// Text scale the price badge / footer is laid out with.
  static double priceBadgeTextScale(double textScale) {
    if (!(textScale > 1.0)) return 1.0;
    return textScale < priceBadgeMaxTextScale
        ? textScale
        : priceBadgeMaxTextScale;
  }

  /// How much taller the card's text block is at [ts] (already clamped to
  /// 1.0..2.0) than at 1.0: [_textBlockGrowth] per scale step, minus the part
  /// of the footer that no longer grows above [priceBadgeMaxTextScale].
  static double _contentGrowth(double ts, {required bool compact}) {
    final footerNotGrown = ts > priceBadgeMaxTextScale
        ? priceFooterHeightPerScale * (ts - priceBadgeMaxTextScale)
        : 0.0;
    return _textBlockGrowth(compact: compact) * (ts - 1.0) - footerNotGrown;
  }

  static double _clampScale(double textScale) =>
      textScale > 1.0 ? (textScale > 2.0 ? 2.0 : textScale) : 1.0;

  /// Text block height for a grid card at system text scale [textScale]. Used
  /// both for the cell height ([gridChildAspectRatioForWidth]) and by the card
  /// itself (`textReserve` in global_listing_card_build.dart) so the two can
  /// never drift apart again.
  static double gridCardTextBlockHeightAt(
    double textScale, {
    bool compact = false,
  }) {
    final ts = _clampScale(textScale);
    final base = compact
        ? gridCardCompactTextBlockHeight
        : gridCardTextBlockHeight;
    return base + _contentGrowth(ts, compact: compact);
  }

  /// Aspect ratio for a listing cell at system text scale [textScale]
  /// (1.0..2.0, see `SystemDisplayLock`). At 1.0 this is exactly
  /// [_baseGridChildAspectRatioForWidth]. Above 1.0 the cell gets taller so
  /// the scaled title / chips / price fit instead of overflowing:
  /// - list (1 column): the card is text rows next to the photo; it grows by
  ///   the content's real growth (title, two chip rows, footer), NOT by
  ///   `height * textScale`. The old `base / textScale` made the card grow
  ///   ~169 dp per scale step on a Pro Max while the content needs ~93 dp, and
  ///   the surplus became a large gap under the title (CarNet TestFlight);
  /// - grid: only the text block under the photo grows.
  static double gridChildAspectRatioForWidth(
    int listingColumns,
    double width, {
    double textScale = 1.0,
  }) {
    final base = _baseGridChildAspectRatioForWidth(listingColumns, width);
    if (!(textScale > 1.0)) return base;
    final ts = _clampScale(textScale);
    final compact = width < _compactPhoneWidth;
    if (listingColumns == 1) {
      // List pages inset the cell by 4 dp on each side.
      final cellW = (width - 8.0).clamp(120.0, 900.0);
      final baseH = cellW / base;
      return cellW / (baseH + _contentGrowth(ts, compact: compact));
    }
    final cols = listingColumns < 2 ? 2 : listingColumns;
    final cellW = ((width - 8.0 * (cols + 1)) / cols).clamp(120.0, 600.0);
    final baseH = cellW / base;
    return cellW / (baseH + _contentGrowth(ts, compact: compact));
  }

  static double _baseGridChildAspectRatioForWidth(
    int listingColumns,
    double width,
  ) {
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
