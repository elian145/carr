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
