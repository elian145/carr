import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.car_listing_app/google_maps_config');

bool? _iosSdkConfiguredCache;

/// Whether the native iOS Maps SDK was initialized with a real-looking API key.
/// When false, do not embed [GoogleMap] on iOS (it hard-crashes without [GMSServices provideAPIKey]).
Future<bool> isIosGoogleMapsSdkConfigured() async {
  if (kIsWeb || !Platform.isIOS) return true;
  final cached = _iosSdkConfiguredCache;
  if (cached != null) return cached;
  // Channel is registered after the Flutter engine attaches; retry briefly to avoid a false negative.
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      final dynamic v = await _channel.invokeMethod('isIosGoogleMapsSdkConfigured');
      final ok = v == true;
      _iosSdkConfiguredCache = ok;
      return ok;
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    } catch (_) {
      _iosSdkConfiguredCache = false;
      return false;
    }
  }
  _iosSdkConfiguredCache = false;
  return false;
}
