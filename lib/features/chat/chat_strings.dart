import 'package:flutter/material.dart';

/// Lightweight chat copy helper (en / ar / ku) used by leaf widgets and pages.
String chatText(BuildContext context, String en, {String? ar, String? ku}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String formatVoiceDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

bool isIgnorableSocketError(String err) {
  final text = err.toLowerCase();
  return text.contains('was not upgraded to websocket') ||
      text.contains('transport=websocket');
}

String formatSocketErrorForUser(String err) {
  final text = err.toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('no address associated with hostname') ||
      text.contains('network is unreachable')) {
    return 'Cannot reach CarNet server. Check Wi‑Fi or mobile data, then open '
        'https://carr-5hrm.onrender.com in Safari.';
  }
  return err;
}
