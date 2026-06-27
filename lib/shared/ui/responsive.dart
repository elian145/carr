import 'package:flutter/material.dart';

import '../prefs/listing_layout_prefs.dart';

/// Layout helpers so UI stays consistent and overflow-free across phone sizes.
abstract final class AppResponsive {
  static const double _dialogHorizontalInset = 24;
  static const double _dialogVerticalInset = 48;

  static Size screenSize(BuildContext context) => MediaQuery.sizeOf(context);

  static double dialogWidth(BuildContext context, {double preferred = 400}) {
    final maxW = screenSize(context).width - _dialogHorizontalInset * 2;
    return preferred.clamp(280, maxW);
  }

  static double dialogMaxHeight(BuildContext context, {double fraction = 0.85}) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final h = screenSize(context).height - viewPadding.top - viewPadding.bottom;
    return (h * fraction).clamp(280, h - _dialogVerticalInset);
  }

  /// Height for scrollable picker content inside a dialog header + footer.
  static double dialogScrollHeight(
    BuildContext context, {
    double preferred = 380,
    double headerFooterReserve = 120,
  }) {
    final max = dialogMaxHeight(context) - headerFooterReserve;
    return preferred.clamp(160, max);
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
    final w = dialogWidth(context, preferred: preferredDialogWidth) - 40;
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

  static double featuredCarouselHeight(BuildContext context) {
    return homeGridListingCardHeight(context);
  }

  static double featuredCardWidth(BuildContext context) {
    return homeGridListingCardWidth(context);
  }

  /// Matches a single cell in the home 2-column listing grid.
  static double homeGridListingCardWidth(BuildContext context) {
    final w = screenSize(context).width;
    return ((w - 24) / 2).clamp(160, 210);
  }

  static double homeGridListingCardHeight(BuildContext context) {
    final width = homeGridListingCardWidth(context);
    return width / ListingLayoutPrefs.gridChildAspectRatio(2);
  }

  static double listingGridImageHeight(
    BuildContext context, {
    bool quickSell = false,
    double? maxHeight,
  }) {
    final w = screenSize(context).width;
    final colW = (w - 24) / 2;
    final ratio = quickSell ? 0.62 : 0.88;
    var height = (colW * ratio).clamp(
      quickSell ? 100.0 : 140.0,
      quickSell ? 130.0 : 190.0,
    );
    if (maxHeight != null && maxHeight.isFinite) {
      height = height.clamp(
        quickSell ? 100.0 : 120.0,
        maxHeight.clamp(quickSell ? 100.0 : 120.0, 190.0),
      );
    }
    return height;
  }

  static double previewHeroHeight(BuildContext context) {
    return (screenSize(context).height * 0.35).clamp(220, 300);
  }

  /// Tighter app bar button padding on narrow phones (labels always stay visible).
  static bool narrowAppBar(BuildContext context) {
    return screenSize(context).width < 380;
  }

  /// Lock text scale so typography and layout match across devices.
  static Widget wrapApp(BuildContext context, Widget child) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.noScaling),
      child: child,
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
      height: AppResponsive.dialogMaxHeight(
        context,
        fraction: heightFraction,
      ),
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
    return ConstrainedBox(
      constraints: constraints,
      child: content,
    );
  }
}
