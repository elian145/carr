import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Locks out phone Font size and Display size so layouts keep designed dp.
abstract final class SystemDisplayLock {
  static const _channel = MethodChannel('carzo/display_lock');
  static Future<void>? _initFuture;
  static double? _stableDevicePixelRatio;

  static Future<void> init() {
    if (_stableDevicePixelRatio != null) {
      return Future.value();
    }
    return _initFuture ??= _loadStableDensity().whenComplete(() {
      if (_stableDevicePixelRatio == null) {
        _initFuture = null;
      }
    });
  }

  static Future<void> _loadStableDensity() async {
    if (kIsWeb) return;
    try {
      final dpi = await _channel.invokeMethod<int>('getStableDensityDpi');
      if (dpi != null && dpi > 0) {
        _stableDevicePixelRatio = dpi / 160.0;
      }
    } on MissingPluginException {
      // Tests / platforms without the Android channel.
    } catch (_) {}
  }

  @visibleForTesting
  static set debugStableDevicePixelRatio(double? value) {
    _stableDevicePixelRatio = value;
    _initFuture = value == null ? null : Future.value();
  }

  /// Paint scale so designed dp stays the same number of physical pixels when
  /// Android Display size has changed the engine DPR.
  static double visualScaleOf(MediaQueryData mq) {
    final stableDpr = _stableDevicePixelRatio;
    final currentDpr = mq.devicePixelRatio;
    if (stableDpr == null ||
        stableDpr <= 0 ||
        currentDpr <= 0 ||
        (currentDpr - stableDpr).abs() < 0.02) {
      return 1.0;
    }
    return stableDpr / currentDpr;
  }

  /// Ignore system text scale; restore logical size when Android Display size
  /// changed the density.
  static MediaQueryData lock(MediaQueryData mq) {
    var data = mq.copyWith(textScaler: TextScaler.noScaling);
    final scale = visualScaleOf(mq);
    if ((scale - 1.0).abs() < 0.02) {
      return data;
    }
    final f = 1.0 / scale;
    return data.copyWith(
      size: Size(mq.size.width * f, mq.size.height * f),
      devicePixelRatio: _stableDevicePixelRatio,
      padding: _scaleInsets(mq.padding, f),
      viewPadding: _scaleInsets(mq.viewPadding, f),
      viewInsets: _scaleInsets(mq.viewInsets, f),
      systemGestureInsets: _scaleInsets(mq.systemGestureInsets, f),
    );
  }

  static EdgeInsets _scaleInsets(EdgeInsets insets, double f) {
    return EdgeInsets.fromLTRB(
      insets.left * f,
      insets.top * f,
      insets.right * f,
      insets.bottom * f,
    );
  }
}
