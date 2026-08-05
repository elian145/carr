import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../auth/phone_verification_gate.dart';

String userErrorText(
  BuildContext context,
  Object error, {
  String? fallback,
}) {
  final loc = AppLocalizations.of(context);
  final fallbackText = fallback ?? loc?.errorTitle ?? 'Error';

  String normalize(String value) {
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .trim();
  }

  if (error is ApiException) {
    if (isPhoneVerificationRequired(error)) {
      return phoneVerificationRequiredMessage(loc);
    }
    // Raw 401 bodies are JWT internals ("Token has expired"); say what to do.
    if (error.statusCode == 401) {
      return loc?.authenticationRequired ?? fallbackText;
    }
    final msg = normalize(error.message);
    if (msg.isEmpty) return fallbackText;
    if (error.statusCode >= 400 && error.statusCode < 500) {
      return msg;
    }
    // Surface short, clean 5xx API messages (e.g. OTP/SMS failures).
    final lower = msg.toLowerCase();
    if (error.statusCode >= 500 &&
        msg.length <= 160 &&
        !msg.contains('\n') &&
        !lower.contains('exception') &&
        !lower.contains('traceback') &&
        !lower.contains('stack')) {
      return msg;
    }
    return fallbackText;
  }

  // Anything that is not an ApiException is an internal/plugin failure, so it
  // is never shown verbatim. Deliberate user-facing errors should be thrown as
  // ApiException so the branch above can surface them.
  return fallbackText;
}
