import 'package:flutter/widgets.dart';

/// Returns [input] with digits localized for the current locale.
/// For ar/ku we keep Western digits (0-9) to avoid garbled display (Mojibake)
/// on some devices where Arabic-Indic numerals were mis-rendered.
String localizeDigits(BuildContext context, String input) {
  // Previously converted to Arabic-Indic (٠١٢٣...) for ar/ku, but that caused
  // garbled text (UTF-8 misinterpreted). Keeping Western digits for consistency.
  return input;
}
