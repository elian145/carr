import 'package:flutter/widgets.dart';

/// Lightweight helpers for translating UI snippets not covered by [AppLocalizations].
String trLegacyText(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String yesText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'نعم';
  if (code == 'ku') return 'بەڵێ';
  return 'Yes';
}

String noText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return 'لا';
  if (code == 'ku') return 'نەخێر';
  return 'No';
}
