import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

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
    final msg = normalize(error.message);
    if (msg.isNotEmpty && error.statusCode >= 400 && error.statusCode < 500) {
      return msg;
    }
    return fallbackText;
  }

  final raw = normalize(error.toString());
  if (raw.isEmpty) return fallbackText;

  // Avoid leaking transport/system internals directly to end users.
  final lower = raw.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('typeerror') ||
      lower.contains('handshake') ||
      lower.contains('stack') ||
      lower.contains('null check operator')) {
    return fallbackText;
  }

  return fallbackText;
}
