import 'package:flutter/material.dart';

import '../../state/locale_controller.dart' as app_state;

Widget buildLanguageMenu() {
  return PopupMenuButton<String>(
    icon: const Icon(Icons.language),
    onSelected: (code) {
      app_state.LocaleController.setLocale(Locale(code));
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'en', child: Text('English')),
      PopupMenuItem(value: 'ar', child: Text('العربية')),
      PopupMenuItem(value: 'ku', child: Text('کوردی')),
    ],
  );
}
