import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<String?> showDeleteAccountPasswordDialog(BuildContext context) {
  return showDialog<String?>(
    context: context,
    builder: (ctx) {
      final passwordController = TextEditingController();
      final loc = AppLocalizations.of(ctx)!;
      return AlertDialog(
        title: Text(loc.deleteAccountTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.deleteAccountBody),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: loc.passwordOptionalConfirm,
                  hintText: loc.confirmWithPasswordHint,
                ),
                obscureText: true,
                autocorrect: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, passwordController.text.trim()),
            child: Text(
              loc.deleteMyAccount,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    },
  );
}
