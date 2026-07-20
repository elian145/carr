import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Returns the trimmed password, or `null` if the user cancelled.
/// Empty password is not allowed — caller should treat cancel and empty the same.
Future<String?> showDeleteAccountPasswordDialog(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<String?>(
    context: context,
    builder: (ctx) {
      final passwordController = TextEditingController();
      final formKey = GlobalKey<FormState>();
      return Semantics(
        namesRoute: true,
        label: loc.deleteAccountTitle,
        child: AlertDialog(
        title: Text(loc.deleteAccountTitle),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.deleteAccountBody),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: loc.passwordRequiredConfirm,
                    hintText: loc.confirmWithPasswordHint,
                  ),
                  obscureText: true,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return loc.passwordRequiredConfirm;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(ctx, passwordController.text.trim());
            },
            child: Text(
              loc.deleteMyAccount,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
      );
    },
  );
}
