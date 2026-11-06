part of 'websocket_service.dart';

const bool kSideloadBuild = bool.fromEnvironment(
  'SIDELOAD_BUILD',
  defaultValue: false,
);

DateTime parseApiDateTime(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return DateTime.now();
  try {
    final parsed = DateTime.parse(text);
    final hasTimezone =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(text);
    if (hasTimezone) {
      return parsed.toLocal();
    }
    // Backend stores naive UTC timestamps; interpret them as UTC.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toLocal();
  } catch (e, st) { logNonFatal(e, st); 
    return DateTime.now();
  }
}

/// Nullable variant of [parseApiDateTime] for fields that are legitimately
/// absent: `null` for null/empty/unparseable input, otherwise the same
/// (verified) interpretation - offset-less API strings are UTC, `Z`/offset
/// strings are honoured - returned as a local [DateTime].
DateTime? tryParseApiDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final text = raw.toString().trim();
  if (text.isEmpty || DateTime.tryParse(text) == null) return null;
  return parseApiDateTime(text);
}
