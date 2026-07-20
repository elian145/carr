import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// App-wide network reachability (best-effort; Wi‑Fi without internet still reports online).
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final initial = await Connectivity().checkConnectivity();
      _apply(initial);
      _sub = Connectivity().onConnectivityChanged.listen(_apply);
    } catch (_) {
      isOnline.value = true;
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (isOnline.value != online) {
      isOnline.value = online;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
