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
      _sub = Connectivity().onConnectivityChanged.listen(
        _apply,
        // B-08: a stream error must not be silently swallowed into a
        // stale/default "online" value — fail conservatively toward
        // offline, matching the initial-check catch below.
        onError: (_) => _markOffline(),
      );
    } catch (_) {
      // B-08: a plugin/check failure must NOT be reported as online — that
      // hides a genuine offline state from the rest of the app (chat/Sell
      // recovery triggers, API error/cache messaging, the offline banner,
      // etc). Fail conservatively toward offline instead.
      _markOffline();
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (isOnline.value != online) {
      isOnline.value = online;
    }
  }

  void _markOffline() {
    if (isOnline.value) {
      isOnline.value = false;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
