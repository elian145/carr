import 'package:flutter/material.dart';

/// How a brand-picker caption is laid out inside a fixed-width tile.
@immutable
class BrandLabelPlan {
  const BrandLabelPlan(this.fontSize, this.maxLines, this.lineHeight);

  final double fontSize;
  final int maxLines;

  /// Line-height multiplier (only meaningful when [maxLines] > 1).
  final double lineHeight;

  @override
  String toString() => 'BrandLabelPlan($fontSize sp x $maxLines lines)';
}

/// Caption under a round brand logo in the Sell / Filters / Search pickers.
///
/// Tiles are 72 dp wide and the grid rows are a fixed 92 dp tall (52 dp coin +
/// 2 dp ring + 8 dp gap leaves [maxHeight] = 30 dp), so the four-column grid
/// must not change. Names are laid out in this order of preference:
///
///  1. one line at 12 sp, shrinking by at most 12 -> 10.5 sp (what the old
///     scale-to-fit label did for names that are a little too long);
///  2. two lines of 12..10 sp, only breaking between words;
///  3. three lines at 10 sp (e.g. "Zyle Daewoo Commercial Vehicle", which used
///     to be scaled down to ~4.5 sp on a single line).
///
/// Text never scales with the system font size (same as the label it replaces)
/// so a large accessibility font cannot grow the tile and break the grid.
class BrandTileLabel extends StatelessWidget {
  const BrandTileLabel(
    this.text, {
    super.key,
    required this.color,
    this.fontWeight = FontWeight.w600,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;

  static const double baseFontSize = 12;
  static const double minSingleLineFontSize = 10.5;
  static const double maxHeight = 30;

  /// Chooses the layout for [text] in a tile [maxWidth] dp wide.
  @visibleForTesting
  static BrandLabelPlan plan({
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    double measure(double size, {int lines = 1, double height = 1.0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: size, height: lines > 1 ? height : null),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: lines,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: lines == 1 ? double.infinity : maxWidth);
      final exceeded = tp.didExceedMaxLines;
      final w = tp.width;
      final h = tp.height;
      tp.dispose();
      if (exceeded) return double.infinity;
      return lines == 1 ? w : h;
    }

    double longestWord(double size) {
      var longest = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(text: word, style: style.copyWith(fontSize: size)),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        if (tp.width > longest) longest = tp.width;
        tp.dispose();
      }
      return longest;
    }

    // 1) single line, shrinking a little.
    for (var s = baseFontSize; s >= minSingleLineFontSize - 0.001; s -= 0.25) {
      if (measure(s) <= maxWidth + 0.01) return BrandLabelPlan(s, 1, 1.0);
    }
    // 2) two lines, word breaks only.
    for (final s in const [12.0, 11.5, 11.0, 10.5, 10.0]) {
      if (longestWord(s) > maxWidth) continue;
      if (measure(s, lines: 2, height: 1.05) <= maxHeight + 0.01) {
        return BrandLabelPlan(s, 2, 1.05);
      }
    }
    // 3) three lines at 10 sp.
    return const BrandLabelPlan(10, 3, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: baseFontSize,
      fontWeight: fontWeight,
      color: color,
    );
    // Measure with the font the Text will really use (theme / app font), not
    // the engine default, or wrapping decisions would be made for another font.
    final measureStyle = DefaultTextStyle.of(context).style.merge(base);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : 72.0;
        final p = plan(text: text, style: measureStyle, maxWidth: width);
        return SizedBox(
          width: double.infinity,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: p.maxLines,
            softWrap: p.maxLines > 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: base.copyWith(
              fontSize: p.fontSize,
              height: p.maxLines > 1 ? p.lineHeight : null,
            ),
          ),
        );
      },
    );
  }
}
