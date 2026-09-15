import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'expected_client_noise.dart';

/// Logs only in debug builds. Prefer this over [debugPrint] / [print] in services.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Test-only interception point for [logNonFatal]. When set, [logNonFatal]
/// hands the error/stack trace/context to this callback instead of calling
/// `Sentry.captureException`, so tests can assert exactly what would have
/// been reported without depending on a real/initialized Sentry client.
/// Always `null` in production; mirrors this repo's existing
/// `@visibleForTesting` override convention (e.g.
/// `AuthService.debugProfileRetryDelaysOverride`).
@visibleForTesting
void Function(Object error, StackTrace? stackTrace, String? context)?
    debugLogNonFatalOverride;

/// Records a non-fatal error without changing user-visible behavior.
void logNonFatal(
  Object error, [
  StackTrace? stackTrace,
  String? context,
]) {
  final prefix = context != null ? '[$context] ' : '';
  if (isExpectedClientNoise(error)) {
    appLog('Non-fatal (expected) $prefix$error');
    return;
  }
  if (kDebugMode) {
    debugPrint('Non-fatal $prefix$error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
  final override = debugLogNonFatalOverride;
  if (override != null) {
    override(error, stackTrace, context);
    return;
  }
  try {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      hint: context != null ? Hint.withMap({'context': context}) : null,
    );
  } catch (_) {}
}
