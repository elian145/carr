import 'package:flutter/widgets.dart';

String localizeDigits(BuildContext context, String input) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode == 'ar' || locale.languageCode == 'ku') {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ','];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩', '،'];
    String out = input;
    for (int i = 0; i < western.length; i++) {
      out = out.replaceAll(western[i], eastern[i]);
    }
    return out;
  }
  return input;
}
