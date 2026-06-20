import 'package:flutter/widgets.dart';

void dismissAnyKeyboard([BuildContext? context]) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null && focus.hasFocus) {
    focus.unfocus();
  }
  if (context != null && context.mounted) {
    FocusScope.of(context).unfocus();
  }
}
