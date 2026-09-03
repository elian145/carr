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
  ///
  /// Also keeps [MediaQueryData.padding] bottom at least [viewPadding] when the
  /// keyboard is closed so Android edge-to-edge / 3-button nav does not cover
  /// bottom controls (SafeArea and `padding.bottom` callers).
  static MediaQueryData lock(MediaQueryData mq) {
    var data = mq.copyWith(textScaler: TextScaler.noScaling);
    data = _ensureBottomSystemInset(data);
    final scale = visualScaleOf(mq);
    if ((scale - 1.0).abs() < 0.02) {
      return data;
    }
    final f = 1.0 / scale;
    return data.copyWith(
      size: Size(data.size.width * f, data.size.height * f),
      devicePixelRatio: _stableDevicePixelRatio,
      padding: _scaleInsets(data.padding, f),
      viewPadding: _scaleInsets(data.viewPadding, f),
      viewInsets: _scaleInsets(data.viewInsets, f),
      systemGestureInsets: _scaleInsets(data.systemGestureInsets, f),
    );
  }

  /// When the IME is hidden, some Android builds report `padding.bottom == 0`
  /// while the system nav still overlays the window. Prefer viewPadding.
  static MediaQueryData _ensureBottomSystemInset(MediaQueryData mq) {
    if (mq.viewInsets.bottom > 0) return mq;
    final bottom = mq.viewPadding.bottom;
    if (bottom <= mq.padding.bottom) return mq;
    return mq.copyWith(padding: mq.padding.copyWith(bottom: bottom));
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
