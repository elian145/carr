import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../errors/user_error_text.dart';

/// Confirms ownership of [newPhone] with an SMS code sent to that number,
/// then applies the change through [AuthService]. Returns `true` once the
/// phone number has been updated, or `false`/`null` if the user cancelled.
///
/// Unlike [showEmailChangeConfirmDialog], there is no separate "verify"
/// endpoint here: the server applies the change directly through
/// `PUT /api/user/profile` once a valid `verification_code` (from
/// `POST /api/user/phone-change/send-code`) is supplied.
Future<bool> showPhoneChangeConfirmDialog(
  BuildContext context, {
  required AuthService auth,
  required String newPhone,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PhoneChangeDialog(auth: auth, newPhone: newPhone),
  );
  return result ?? false;
}

class _PhoneChangeDialog extends StatefulWidget {
  const _PhoneChangeDialog({required this.auth, required this.newPhone});

  final AuthService auth;
  final String newPhone;

  @override
  State<_PhoneChangeDialog> createState() => _PhoneChangeDialogState();
}

class _PhoneChangeDialogState extends State<_PhoneChangeDialog> {
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
      await widget.auth.sendAccountPhoneChangeCode(widget.newPhone);
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
      await widget.auth.updateProfile({
        'phone_number': widget.newPhone,
        'verification_code': _codeController.text.trim(),
      });
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
      label: loc.verifyNewPhoneDialogTitle,
      child: AlertDialog(
        title: Text(loc.verifyNewPhoneDialogTitle),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.verifyNewPhoneDialogMessage(widget.newPhone)),
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
