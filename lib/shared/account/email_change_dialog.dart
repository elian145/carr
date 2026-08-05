import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../errors/user_error_text.dart';

/// Confirms ownership of [newEmail] with a code sent to that address, then
/// applies the change through [AuthService]. Returns `true` once the email
/// has been updated, or `false`/`null` if the user cancelled.
///
/// The server never accepts a new personal account email without this proof
/// (S7); this dialog is the only path the app uses to change it.
Future<bool> showEmailChangeConfirmDialog(
  BuildContext context, {
  required AuthService auth,
  required String newEmail,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EmailChangeDialog(auth: auth, newEmail: newEmail),
  );
  return result ?? false;
}

class _EmailChangeDialog extends StatefulWidget {
  const _EmailChangeDialog({required this.auth, required this.newEmail});

  final AuthService auth;
  final String newEmail;

  @override
  State<_EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<_EmailChangeDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final loc = AppLocalizations.of(context);
    try {
      await widget.auth.sendAccountEmailChangeCode(widget.newEmail);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(loc?.verificationCodeSent ?? 'Code sent')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userErrorText(context, e, fallback: loc?.error);
      });
    }
  }

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final loc = AppLocalizations.of(context);
    try {
      await widget.auth.verifyAccountEmailChange(
        widget.newEmail,
        _codeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userErrorText(context, e, fallback: loc?.error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Semantics(
      namesRoute: true,
      label: loc.verifyNewEmailDialogTitle,
      child: AlertDialog(
        title: Text(loc.verifyNewEmailDialogTitle),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.verifyNewEmailDialogMessage(widget.newEmail)),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: loc.sixDigitCodeLabel,
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      final digits = (value ?? '').trim();
                      if (digits.length != 6) return loc.pleaseEnter6DigitCode;
                      return null;
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: _busy ? null : _sendCode,
            child: Text(_codeSent ? loc.resend : loc.sendCodeButton),
          ),
          if (_codeSent)
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(loc.verifyButton),
            ),
        ],
      ),
    );
  }
}
