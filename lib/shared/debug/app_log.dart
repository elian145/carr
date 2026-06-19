import 'package:flutter/foundation.dart';

/// Logs only in debug builds. Prefer this over [debugPrint] / [print] in services.
void appLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
