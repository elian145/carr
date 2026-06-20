import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Logs only in debug builds. Prefer this over [debugPrint] / [print] in services.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Records a non-fatal error without changing user-visible behavior.
void logNonFatal(
  Object error, [
  StackTrace? stackTrace,
  String? context,
]) {
  final prefix = context != null ? '[$context] ' : '';
  if (kDebugMode) {
    debugPrint('Non-fatal $prefix$error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
  try {
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      hint: context != null ? Hint.withMap({'context': context}) : null,
    );
  } catch (_) {}
}
