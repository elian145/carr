import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.car_listing_app/google_maps_config');

/// Only cache a positive result. Never cache `false`: the native channel may register
/// after the first frame, and caching false would show the fallback forever until restart.
bool _iosSdkConfiguredPositiveCache = false;

/// Clears the positive cache so the next probe hits the native channel again (e.g. after app resume).
void resetIosGoogleMapsSdkConfiguredCache() {
  _iosSdkConfiguredPositiveCache = false;
}

bool _coerceChannelBool(dynamic v) {
  if (v == true) return true;
  if (v == false || v == null) return false;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

/// Whether the native iOS Maps SDK was initialized with a real-looking API key.
/// When false, do not embed [GoogleMap] on iOS (it hard-crashes without [GMSServices provideAPIKey]).
Future<bool> isIosGoogleMapsSdkConfigured({bool forceRefresh = false}) async {
  if (kIsWeb || !Platform.isIOS) return true;
  if (forceRefresh) {
    _iosSdkConfiguredPositiveCache = false;
  }
  if (_iosSdkConfiguredPositiveCache) return true;

  // Channel is registered after the Flutter engine attaches; retry to avoid a false negative.
  for (var attempt = 0; attempt < 25; attempt++) {
    try {
      final dynamic v = await _channel.invokeMethod<dynamic>('isIosGoogleMapsSdkConfigured');
      final ok = _coerceChannelBool(v);
      if (ok) {
        _iosSdkConfiguredPositiveCache = true;
      }
      return ok;
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } catch (_) {
      // Transient errors: do not cache failure; caller can retry (e.g. new FutureBuilder).
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  return false;
}
