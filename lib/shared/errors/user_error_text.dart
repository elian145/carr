import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

bool _isDuplicateVinMessage(String lower) {
  return lower.contains('car_vin_key') ||
      (lower.contains('uniqueviolation') && lower.contains('vin')) ||
      (lower.contains('vin') &&
          lower.contains('already exists') &&
          (lower.contains('duplicate') || lower.contains('unique')));
}

String userErrorText(
  BuildContext context,
  Object error, {
  String? fallback,
}) {
  final loc = AppLocalizations.of(context);
  final fallbackText = fallback ?? loc?.errorTitle ?? 'Error';
  final vinDuplicateText = loc?.listingVinAlreadyExists ??
      'This VIN is already used on another listing. Use a different VIN or edit your existing listing.';

  String normalize(String value) {
    return value
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '')
        .trim();
  }

  if (error is ApiException) {
    final msg = normalize(error.message);
    final lower = msg.toLowerCase();
    if (_isDuplicateVinMessage(lower)) {
      return vinDuplicateText;
    }
    if (msg.isNotEmpty && error.statusCode >= 400 && error.statusCode < 500) {
      return msg;
    }
    return fallbackText;
  }

  final raw = normalize(error.toString());
  if (raw.isEmpty) return fallbackText;

  // Avoid leaking transport/system internals directly to end users.
  final lower = raw.toLowerCase();
  if (_isDuplicateVinMessage(lower)) {
    return vinDuplicateText;
  }
  if (lower.contains('socket') ||
      lower.contains('typeerror') ||
      lower.contains('handshake') ||
      lower.contains('stack') ||
      lower.contains('null check operator') ||
      lower.contains('psycopg2') ||
      lower.contains('insert into car') ||
      lower.contains('failed to create car listing:')) {
    return fallbackText;
  }

  return fallbackText;
}
