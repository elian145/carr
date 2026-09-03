import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Runtime knobs that keep mid/low-end Android smooth without gutting iOS polish.
class DevicePerformance {
  DevicePerformance._();

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Live [BackdropFilter] on chrome is expensive while scrolling on many Android GPUs.
  static bool get preferSolidChrome => isAndroid;

  /// Cap decoded-image cache so 4GB devices do not thrash under GC pressure.
  static void configureImageCache() {
    if (!isAndroid) return;
    final cache = PaintingBinding.instance.imageCache;
    // Default Flutter cache can grow well past 100MB; keep a tighter ceiling.
    cache.maximumSizeBytes = 80 * 1024 * 1024;
    cache.maximumSize = 120;
  }
}
