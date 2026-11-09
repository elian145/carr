import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Locks out phone Display size (density) so layouts keep designed dp, and
/// bounds the phone Font size to [minTextScale]..[maxTextScale] (it is
/// honoured, not locked).
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

  /// Smallest / largest system text scale the app honours.
  ///
  /// Floor 1.0: layouts are designed at 1.0 and were never tuned for smaller
  /// text, so a "small" system font simply renders at the designed size.
  /// Ceiling 2.0: Android's largest Font size setting is ~2.0 (nonlinear
  /// scaling since Android 14 also tops out at 2.0) and WCAG 1.4.4 asks for
  /// 200% resize, so every content screen must work at 2.0. Anything beyond
  /// (third-party OEM sliders, adb overrides) is clamped here so a single
  /// absurd value can never make the UI unusable.
  static const double minTextScale = 1.0;
  static const double maxTextScale = 2.0;

  /// Pure clamp used by [lock]. Non-finite / non-positive input falls back to
  /// the designed size (1.0).
  static double clampTextScale(double factor) {
    if (factor.isNaN || factor.isInfinite || factor <= 0) return 1.0;
    return factor.clamp(minTextScale, maxTextScale).toDouble();
  }

  /// Effective linear factor of [scaler] for body-sized text (14 sp), so
  /// Android 14+ nonlinear scalers are represented by what users actually
  /// read rather than by a 1 sp probe.
  static double textScaleFactorOf(TextScaler scaler) {
    const probe = 14.0;
    return scaler.scale(probe) / probe;
  }

  /// Respect the system text scale between [minTextScale] (1.0) and
  /// [maxTextScale] (2.0). Also restores logical size
  /// when Android Display size changed the density.
  ///
  /// Also keeps [MediaQueryData.padding] bottom at least [viewPadding] when the
  /// keyboard is closed so Android edge-to-edge / 3-button nav does not cover
  /// bottom controls (SafeArea and `padding.bottom` callers).
  ///
  /// Deliberately does NOT use [TextScaler.clamp] here: that returns a
  /// `_ClampedTextScaler`, and some framework widgets (e.g.
  /// `BottomNavigationBar`'s label text) call `.clamp(maxScaleFactor: 1.0)`
  /// on the *inherited* scaler again internally. `_ClampedTextScaler.clamp()`
  /// only compares its own raw min/max arguments for equality before
  /// computing the actual intersected bounds, so when our lower bound
  /// (1.0) and the nested call's upper bound (1.0) intersect to an equal
  /// range, its constructor's `assert(maxScale > minScale)` fires - the
  /// known `_ClampedTextScaler` assertion. Resolving the clamp to a plain
  /// scale factor and wrapping it in [TextScaler.linear] keeps the exact
  /// same effective scaling (clamped to [1.0, 2.0]) while avoiding
  /// that nested-clamp code path entirely, since `_LinearTextScaler.clamp()`
  /// has no such bug.
  static MediaQueryData lock(MediaQueryData mq) {
    final clampedFactor = clampTextScale(textScaleFactorOf(mq.textScaler));
    final clampedScale = TextScaler.linear(clampedFactor);
    var data = mq.copyWith(textScaler: clampedScale);
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
