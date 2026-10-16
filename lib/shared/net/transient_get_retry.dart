import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/api_exception.dart';
import '../debug/expected_client_noise.dart';

/// True for failures of an idempotent GET that say nothing about the
/// resource or the session: timeouts, dropped/refused/reset sockets, a client
/// the OS recycled while the app was backgrounded, and gateway-style 5xx /
/// 408 / 429 answers (a transient session-refresh failure is surfaced by
/// `ApiService` as a 503, so it is covered too).
///
/// A definitive 401/403/404/4xx is NOT transient -- retrying cannot help and
/// would only delay the real error.
bool isTransientGetError(Object error) {
  if (error is ApiCancelledException) return false;
  if (error is TimeoutException) return true;
  if (error is ApiException) {
    final code = error.statusCode;
    return code == 408 ||
        code == 429 ||
        code == 500 ||
        code == 502 ||
        code == 503 ||
        code == 504;
  }
  return isTransientNetworkError(error);
}

/// Pause before each retry; the list length is the retry budget (so at most
/// `length + 1` attempts in total -- never an unbounded loop).
const List<Duration> kTransientGetRetryDelays = <Duration>[
  Duration(milliseconds: 600),
  Duration(seconds: 2),
];

/// Test-only override for [kTransientGetRetryDelays]. Always `null` in
/// production.
@visibleForTesting
List<Duration>? debugTransientGetRetryDelays;

/// Runs [action] (which MUST be a safe, idempotent GET), retrying a
/// [isTransientGetError] failure with the bounded [kTransientGetRetryDelays]
/// budget. Stops early -- rethrowing the last error -- when [isSuperseded]
/// reports the caller no longer cares (a newer request replaced this one), so
/// a stale request never keeps hammering the network.
///
/// [onRetry] runs before each pause (e.g. to recycle a dead HTTP client).
Future<T> retryTransientGet<T>(
  Future<T> Function() action, {
  bool Function()? isSuperseded,
  void Function(Object error, int attempt)? onRetry,
}) async {
  final delays = debugTransientGetRetryDelays ?? kTransientGetRetryDelays;
  for (var attempt = 0;; attempt++) {
    Object error;
    StackTrace stack;
    try {
      return await action();
    } catch (e, st) {
      error = e;
      stack = st;
    }
    final giveUp = !isTransientGetError(error) ||
        attempt >= delays.length ||
        (isSuperseded?.call() ?? false);
    if (giveUp) {
      Error.throwWithStackTrace(error, stack);
    }
    onRetry?.call(error, attempt);
    await Future<void>.delayed(delays[attempt]);
    if (isSuperseded?.call() ?? false) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}
