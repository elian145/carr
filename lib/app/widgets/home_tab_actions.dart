import 'package:flutter/foundation.dart';

/// Cross-route hooks for the Home tab inside [MainShell] (avoids import cycles).
class HomeTabActions {
  HomeTabActions._();

  static VoidCallback? onScrollToTop;

  static void scrollToTop() => onScrollToTop?.call();
}
