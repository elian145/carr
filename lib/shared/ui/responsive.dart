import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../prefs/listing_layout_prefs.dart';
import 'keyboard.dart';

/// Layout helpers so UI stays consistent and overflow-free across phone sizes.
abstract final class AppResponsive {
  static const double _dialogHorizontalInset = 24;
  static const double _dialogVerticalInset = 48;
  static const double compactPhoneWidth = 360;
  static const double narrowPhoneWidth = 380;
  static const double phoneWidth = 600;
  /// Shortest edge where listing grids go to 3 columns (tablet / landscape phone).
  static const double tabletWidth = 720;
  /// Wide tablet / desktop — 4-column listing grids.
  static const double largeTabletWidth = 1000;
  /// Max width for auth / settings form columns on large screens (UI-04).
  static const double formContentMaxWidth = 480;
  static const double settingsContentMaxWidth = 640;

  static Size screenSize(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isCompactPhone(BuildContext context) {
    return screenSize(context).width < compactPhoneWidth;
  }

  static bool isNarrowPhone(BuildContext context) {
    return screenSize(context).width < narrowPhoneWidth;
  }

  static bool isPhone(BuildContext context) {
    return screenSize(context).width < phoneWidth;
  }

  static bool isTablet(BuildContext context) {
    return screenSize(context).width >= tabletWidth;
  }

  static bool isLargeTablet(BuildContext context) {
    return screenSize(context).width >= largeTabletWidth;
  }

  /// Centers [child] and caps width so forms do not stretch edge-to-edge on tablets.
  static Widget constrainContent(
    Widget child, {
    double maxWidth = formContentMaxWidth,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  static double availableWidth(
    BuildContext context, {
    double horizontalInset = 0,
  }) {
    return (screenSize(context).width - horizontalInset * 2)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  static EdgeInsets pagePadding(
    BuildContext context, {
    double compact = 12,
    double regular = 16,
    double tablet = 24,
    double largeTablet = 32,
  }) {
    final w = screenSize(context).width;
    final double horizontal;
    if (w < compactPhoneWidth) {
      horizontal = compact;
    } else if (w < tabletWidth) {
      horizontal = regular;
    } else if (w < largeTabletWidth) {
      horizontal = tablet;
    } else {
      horizontal = largeTablet;
    }
    return EdgeInsets.symmetric(horizontal: horizontal);
  }

  static double adaptiveGap(
    BuildContext context, {
    double compact = 8,
    double regular = 12,
  }) {
    return isCompactPhone(context) ? compact : regular;
  }

  static double dialogWidth(BuildContext context, {double preferred = 400}) {
    final maxW = screenSize(context).width - _dialogHorizontalInset * 2;
    final safeMax = maxW.clamp(240.0, double.infinity).toDouble();
    final minW = safeMax < 280 ? safeMax : 280.0;
    return preferred.clamp(minW, safeMax).toDouble();
  }

  static double dialogMaxHeight(
    BuildContext context, {
    double fraction = 0.85,
  }) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final h = screenSize(context).height - viewPadding.top - viewPadding.bottom;
    final safeMax = (h - _dialogVerticalInset)
        .clamp(220.0, double.infinity)
        .toDouble();
    final minH = safeMax < 280 ? safeMax : 280.0;
    return (h * fraction).clamp(minH, safeMax).toDouble();
  }

  /// Height for scrollable picker content inside a dialog header + footer.
  static double dialogScrollHeight(
    BuildContext context, {
    double preferred = 380,
    double headerFooterReserve = 120,
  }) {
    final max = dialogMaxHeight(context) - headerFooterReserve;
    final safeMax = max.clamp(120.0, double.infinity).toDouble();
    final minH = safeMax < 160 ? safeMax : 160.0;
    return preferred.clamp(minH, safeMax).toDouble();
  }

  static BoxConstraints dialogBoxConstraints(
    BuildContext context, {
    double preferredWidth = 400,
    double? maxHeight,
  }) {
    return BoxConstraints(
      maxWidth: dialogWidth(context, preferred: preferredWidth),
      maxHeight: maxHeight ?? dialogMaxHeight(context),
    );
  }

  static int pickerGridCrossAxisCount(
    BuildContext context, {
    int preferred = 4,
    double minCellWidth = 72,
    double preferredDialogWidth = 400,
  }) {
    final w = (dialogWidth(context, preferred: preferredDialogWidth) - 40)
        .clamp(160.0, double.infinity)
        .toDouble();
    final count = (w / minCellWidth).floor();
    return count.clamp(2, preferred);
  }

  static int bodyTypeGridCrossAxisCount(
    BuildContext context, {
    double preferredDialogWidth = 400,
  }) {
    final w = dialogWidth(context, preferred: preferredDialogWidth) - 40;
    if (w < 280) return 2;
    return 3;
  }

  /// Fixed row height for color-picker tiles (swatch + localized label).
  static double colorPickerGridTileExtent(BuildContext context) {
    const swatch = 36.0;
    const gap = 6.0;
    const verticalPad = 16.0;
    const buffer = 8.0;
    final labelLine = MediaQuery.textScalerOf(context).scale(12) * 1.25;
    return verticalPad + swatch + gap + labelLine + buffer;
  }

  static SliverGridDelegateWithFixedCrossAxisCount colorPickerGridDelegate(
    BuildContext context,
  ) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: bodyTypeGridCrossAxisCount(context),
      mainAxisExtent: colorPickerGridTileExtent(context),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );
  }

  /// Full-bleed featured carousel card (image + title/price/specs).
  /// Matches the home featured section horizontal padding (8 + 4 each side).
  static const double featuredSectionHorizontalInset = 12;

  static double featuredCarouselHeight(BuildContext context) {
    final w = featuredCardWidth(context);
    // Keep a wide card: image-dominant, room for larger title/price/specs type.
    // Extra height on narrow phones so stacked title/price + specs aren't cramped.
    final ratio = isNarrowPhone(context) ? 0.88 : 0.76;
    final minH = isNarrowPhone(context) ? 300.0 : 280.0;
    return (w * ratio).clamp(minH, 420.0);
  }

  static double featuredCardWidth(BuildContext context) {
    final sw = screenSize(context).width;
    return (sw - featuredSectionHorizontalInset * 2).clamp(280.0, sw);
  }

  /// Matches a single cell in the home listing grid (2–4 columns by width).
  static double homeGridListingCardWidth(BuildContext context) {
    final w = screenSize(context).width;
    final cols = ListingLayoutPrefs.effectiveColumnsForWidth(2, w);
    final gutter = 8.0 * (cols + 1);
    return ((w - gutter) / cols).clamp(140.0, 320.0);
  }

  static double homeGridListingCardHeight(BuildContext context) {
    final w = screenSize(context).width;
    final cols = ListingLayoutPrefs.effectiveColumnsForWidth(2, w);
    final width = homeGridListingCardWidth(context);
    return width /
        ListingLayoutPrefs.gridChildAspectRatioForWidth(cols, w);
  }

  static double listingGridImageHeight(
    BuildContext context, {
    bool quickSell = false,
    double? maxHeight,
    double? cardWidth,
  }) {
    final w = screenSize(context).width;
    final colW = cardWidth ?? ((w - 24) / 2);
    // Slightly taller than 4:3 on grid tiles so car photos feel less cropped.
    final ratio = quickSell ? 0.62 : 0.82;
    final preferredMin = quickSell ? 100.0 : 120.0;
    final preferredMax = quickSell ? 130.0 : 230.0;
    var height = (colW * ratio).clamp(preferredMin, preferredMax);
    if (maxHeight != null && maxHeight.isFinite) {
      // Cap to the caller budget even when it's below the preferred minimum,
      // so grid text never loses height to an inflexible image floor.
      final cappedMax = maxHeight.clamp(78.0, preferredMax);
      final effectiveMin =
          preferredMin > cappedMax ? cappedMax : preferredMin;
      height = height.clamp(effectiveMin, cappedMax);
    }
    return height;
  }

  static double listingHorizontalImageWidth(
    BuildContext context, {
    required double cardWidth,
    required double cardHeight,
  }) {
    final desiredFourByThreeWidth = cardHeight * 4 / 3;
    final maxFraction = isCompactPhone(context) ? 0.44 : 0.46;
    return desiredFourByThreeWidth.clamp(
      cardWidth * 0.40,
      cardWidth * maxFraction,
    );
  }

  static double previewHeroHeight(BuildContext context) {
    return (screenSize(context).height * 0.35).clamp(220, 300);
  }

  /// Tighter app bar button padding on narrow phones (labels always stay visible).
  static bool narrowAppBar(BuildContext context) {
    return isNarrowPhone(context);
  }

  /// Label that always scales down to fit its width (no first-frame clip).
  ///
  /// Prefer [FittedBox] over AutoSizeText here — AutoSizeText often paints at
  /// full size on the first frame and only shrinks after a rebuild (e.g. tap).
  static Widget fittedLabel(
    String text, {
    required TextStyle style,
    TextAlign textAlign = TextAlign.center,
    double minFontSize = 6,
    int maxLines = 1,
  }) {
    // Keep API compatible; filter tiles stay single-line and scale to width.
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: textAlign == TextAlign.end
            ? Alignment.centerRight
            : (textAlign == TextAlign.start
                  ? Alignment.centerLeft
                  : Alignment.center),
        child: Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines.clamp(1, 2),
          softWrap: maxLines > 1,
          textScaler: const TextScaler.linear(1.0),
          style: style.copyWith(
            fontSize: (style.fontSize ?? 12).clamp(minFontSize, 99),
          ),
        ),
      ),
    );
  }

  /// Wider filter tiles on compact phones so labels stay readable.
  static double filterIconTileWidth(
    BuildContext context,
    double base, {
    double compactBoost = 16,
  }) {
    if (!isCompactPhone(context)) {
      // Still nudge narrow-but-not-compact phones a bit for long labels.
      if (isNarrowPhone(context)) return base + 8;
      return base;
    }
    return base + compactBoost;
  }

  /// Base font size for icon filter tile labels.
  static double filterIconLabelFontSize(
    BuildContext context, {
    double regular = 12,
    bool textOnly = false,
  }) {
    if (textOnly) return isCompactPhone(context) ? 13 : 15;
    return isCompactPhone(context) ? 10 : regular;
  }

  /// Shrinks [text] to fit when horizontal space is tight (e.g. section summaries).
  static Widget fittedLabelShrink(
    String text, {
    required TextStyle style,
    TextAlign textAlign = TextAlign.end,
    double minFontSize = 10,
  }) {
    final maxFontSize = style.fontSize ?? 14;
    return AutoSizeText(
      text,
      textAlign: textAlign,
      maxLines: 1,
      minFontSize: minFontSize,
      maxFontSize: maxFontSize,
      stepGranularity: 0.5,
      style: style,
    );
  }

  /// Min/max system text scale applied app-wide via [wrapApp] (A-03).
  /// Dense cards may still pin [TextScaler.linear] locally where overflow is critical.
  static const double minAppTextScale = 0.85;
  static const double maxAppTextScaleCompact = 1.35;
  static const double maxAppTextScale = 1.5;

  /// Clamp a raw system text scale factor for CarNet layouts.
  static double clampAppTextScaleFactor(
    double scaleFactor, {
    required bool compactPhone,
  }) {
    final maxScale = compactPhone ? maxAppTextScaleCompact : maxAppTextScale;
    return scaleFactor.clamp(minAppTextScale, maxScale).toDouble();
  }

  /// Allow accessibility text scaling, but cap it to keep dense mobile layouts stable.
  static Widget wrapApp(BuildContext context, Widget child) {
    final mq = MediaQuery.of(context);
    const baseFontSize = 14.0;
    final rawScale = mq.textScaler.scale(baseFontSize) / baseFontSize;
    final scaleFactor = clampAppTextScaleFactor(
      rawScale,
      compactPhone: isCompactPhone(context),
    );
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(scaleFactor)),
      child: KeyboardDismissOnTap(child: child),
    );
  }
}

/// Fixed-height dialog shell for layouts that use [Expanded] internally.
class ResponsiveDialogShell extends StatelessWidget {
  const ResponsiveDialogShell({
    super.key,
    required this.child,
    this.preferredWidth = 400,
    this.heightFraction = 0.85,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final double preferredWidth;
  final double heightFraction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppResponsive.dialogWidth(context, preferred: preferredWidth),
      height: AppResponsive.dialogMaxHeight(context, fraction: heightFraction),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Constrains dialog content to the current screen; use as Dialog child.
class ResponsiveDialogBody extends StatelessWidget {
  const ResponsiveDialogBody({
    super.key,
    required this.child,
    this.preferredWidth = 400,
    this.padding = const EdgeInsets.all(20),
    this.scrollable = false,
    this.maxHeight,
  });

  final Widget child;
  final double preferredWidth;
  final EdgeInsets padding;
  final bool scrollable;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final constraints = AppResponsive.dialogBoxConstraints(
      context,
      preferredWidth: preferredWidth,
      maxHeight: maxHeight,
    );
    Widget content = Padding(padding: padding, child: child);
    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }
    return ConstrainedBox(constraints: constraints, child: content);
  }
}
