import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../errors/user_error_text.dart';

/// Confirmation returned by [showDeleteAccountConfirmDialog].
class DeleteAccountConfirmation {
  const DeleteAccountConfirmation({this.code});

  /// SMS code proving control of the account phone.
  final String? code;
}

/// Asks the user to confirm deletion with an SMS code sent to their phone.
///
/// Phone-OTP accounts have a server-generated password they can never type, so
/// the code is the only confirmation that works for every account.
/// Returns `null` if the user cancelled.
Future<DeleteAccountConfirmation?> showDeleteAccountConfirmDialog(
  BuildContext context, {
  required AuthService auth,
}) {
  return showDialog<DeleteAccountConfirmation?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DeleteAccountDialog(auth: auth),
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.auth});

  final AuthService auth;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  bool _codeSent = false;
  String? _sendError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _maskedPhone() {
    final phone = (widget.auth.userPhone ?? '').trim();
    if (phone.length < 4) return phone;
    return '${'•' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
  }

  Future<void> _sendCode() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final loc = AppLocalizations.of(context);
    try {
      await widget.auth.sendDeleteAccountCode();
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _sending = false;
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text(loc?.verificationCodeSent ?? 'Code sent')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = userErrorText(context, e, fallback: loc?.error);
      });
    }
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      DeleteAccountConfirmation(code: _codeController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Semantics(
      namesRoute: true,
      label: loc.deleteAccountTitle,
      child: AlertDialog(
        title: Text(loc.deleteAccountTitle),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.deleteAccountBody),
                const SizedBox(height: 16),
                Text(
                  loc.verifyPhoneDialogMessage(_maskedPhone()),
                  style: theme.textTheme.bodySmall,
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
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
                if (_sendError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _sendError!,
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
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: Text(loc.cancelAction),
          ),
          if (!_codeSent)
            TextButton(
              onPressed: _sending ? null : _sendCode,
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(loc.sendCodeButton),
            )
          else ...[
            TextButton(
              onPressed: _sending ? null : _sendCode,
              child: Text(loc.resend),
            ),
            TextButton(
              onPressed: _confirm,
              child: Text(
                loc.deleteMyAccount,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
