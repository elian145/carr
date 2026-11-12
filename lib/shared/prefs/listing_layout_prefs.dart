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

  /// Largest text scale of the price inside the orange badge. The price
  /// follows the other card text up to here (on the fixed-height rectangular
  /// card the card text itself is capped by its width, see
  /// [rectCardTextScale]); the pill keeps its 1.0x height and only grows as far
  /// as the text needs (price px + 5 dp: 27.5 dp at 1.5x, never more than the
  /// footer row). 1.5x is where that need reaches the 28 dp footer row:
  /// (28 - 5) / 15 sp ~ 1.53, and (26 - 5) / 14 sp = 1.5 for narrow grid tiles.
  static const double priceBadgeMaxTextScale = 1.5;

  /// Text scale the price badge may use at system scale [textScale]
  /// (before the per-card width / city checks).
  static double priceBadgeTextScale(double textScale) {
    if (!(textScale > 1.0)) return 1.0;
    return textScale < priceBadgeMaxTextScale
        ? textScale
        : priceBadgeMaxTextScale;
  }

  /// The price FOOTER ROW (28 dp, 26 dp on narrow grid tiles) keeps its 1.0x
  /// height at every text size - only the pill inside it changes - so the grid
  /// cell reserves no extra room for it.
  static const double priceFooterMaxTextScale = 1.0;

  /// Height of the price footer row per 1.0 of (uncapped) text scale:
  /// `(26 + 2) * scale` in `_listingPriceBadgeStyle`.
  static const double priceFooterHeightPerScale = 28;

  /// How much taller the grid card's text block is at [ts] (already clamped
  /// to 1.0..2.0) than at 1.0: [_textBlockGrowth] per scale step, minus the
  /// part of the footer that does not grow above [priceFooterMaxTextScale].
  /// The grid card's own layout is untouched; its cell just no longer reserves
  /// height for a price footer that stays 28 dp (keeping that height would
  /// reopen the gap between year/mileage and city/price).
  static double _contentGrowth(double ts, {required bool compact}) {
    final footerNotGrown = ts > priceFooterMaxTextScale
        ? priceFooterHeightPerScale * (ts - priceFooterMaxTextScale)
        : 0.0;
    return _textBlockGrowth(compact: compact) * (ts - 1.0) - footerNotGrown;
  }

  // ---- Rectangular (one-per-row) card: FIXED height -----------------------

  /// Top inset of the text column in the list card
  /// (`global_listing_card_build.dart`: `EdgeInsets.fromLTRB(10, 7, 8, 0)`).
  static const double _rectCardTopPad = 7;

  /// Height of the price footer row (`(26 + 2 * tight)` dp, tight = 1 on every
  /// list card) - the largest the footer can be.
  static const double _rectCardFooterHeight = 28;

  /// Breathing room kept between the rows when the text is at its cap.
  static const double _rectCardSlack = 6;

  /// Largest system text scale the list card text ever uses, however tall the
  /// card is.
  static const double rectCardMaxTextScale = 1.5;

  /// Text scale the rectangular card's text column (title, engine/trim chips,
  /// year/mileage, city) is laid out with.
  ///
  /// The card has the SAME height at every system text size
  /// ([gridChildAspectRatioForWidth]), so the text may only grow as far as the
  /// fixed text column can hold: a two-line title, two chip rows and the price
  /// footer, plus [_rectCardSlack]. That is about 1.5x on a Pro Max, 1.3x at
  /// 393 dp and 1.15-1.2x at 360 dp and below. The result is rounded down to
  /// 0.05, never below 1.0 and never above [textScale].
  ///
  /// [cardHeight] is the height of the whole card.
  static double rectCardTextScale({
    required double cardHeight,
    required bool compact,
    required double textScale,
  }) {
    if (!(textScale > 1.0)) return 1.0;
    final chipFont = compact ? 11.0 : 13.0;
    final chipPad = compact ? 10.0 : 12.0;
    final contentH = cardHeight - _rectCardTopPad;
    // title (two lines of 15 x 1.28 sp + 4 dp cushion) + two chip rows +
    // footer + slack
    final fixed = 4.0 + 2 * chipPad + _rectCardFooterHeight + _rectCardSlack;
    final perScale = 15.0 * 1.28 * 2 + 2 * chipFont;
    final fit = (contentH - fixed) / perScale;
    final stepped = (fit * 20).floor() / 20;
    final cap = stepped.clamp(1.0, rectCardMaxTextScale).toDouble();
    return textScale < cap ? textScale : cap;
  }

  /// Splits [total] among slots in the ratio of [weights] (like `Expanded`
  /// flex) but never gives a slot less than its entry in [mins]; the space
  /// taken by the raised slots comes out of the others. If even the minimums
  /// do not fit they are scaled down together. Always sums to [total].
  static List<double> rectCardSlotHeights({
    required double total,
    required List<double> weights,
    required List<double> mins,
  }) {
    assert(weights.length == mins.length);
    final n = weights.length;
    final out = List<double>.filled(n, 0);
    final fixed = List<bool>.filled(n, false);
    var remaining = total;
    for (var pass = 0; pass <= n; pass++) {
      var weightSum = 0.0;
      for (var i = 0; i < n; i++) {
        if (!fixed[i]) weightSum += weights[i];
      }
      if (weightSum <= 0) break;
      var raised = false;
      for (var i = 0; i < n; i++) {
        if (fixed[i]) continue;
        if (remaining * weights[i] / weightSum < mins[i]) {
          fixed[i] = true;
          out[i] = mins[i];
          remaining -= mins[i];
          raised = true;
        }
      }
      if (!raised) {
        for (var i = 0; i < n; i++) {
          if (!fixed[i]) out[i] = remaining * weights[i] / weightSum;
        }
        break;
      }
    }
    final sum = out.fold<double>(0, (a, b) => a + b);
    if (sum > 0 && (sum - total).abs() > 1e-9) {
      final k = total / sum;
      for (var i = 0; i < n; i++) {
        out[i] *= k;
      }
    }
    return out;
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
  /// - list (1 column): the cell keeps its 1.0x height at EVERY text scale
  ///   (CarNet TestFlight: cards must not grow with iOS Larger Text). The card
  ///   text instead follows the system size up to what that height can hold,
  ///   see [rectCardTextScale];
  /// - grid: only the text block under the photo grows.
  static double gridChildAspectRatioForWidth(
    int listingColumns,
    double width, {
    double textScale = 1.0,
  }) {
    final base = _baseGridChildAspectRatioForWidth(listingColumns, width);
    if (!(textScale > 1.0)) return base;
    // Fixed-height rectangular card: same ratio at every text scale.
    if (listingColumns == 1) return base;
    final ts = _clampScale(textScale);
    final compact = width < _compactPhoneWidth;
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
