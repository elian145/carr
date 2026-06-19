import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../errors/user_error_text.dart';

const String kPhoneVerificationRequiredCode = 'phone_verification_required';

bool isPhoneVerificationRequired(Object? error) {
  if (error is ApiException) {
    if (error.errorCode == kPhoneVerificationRequiredCode) return true;
    if (error.statusCode == 403 &&
        error.message.toLowerCase().contains('verify your phone')) {
      return true;
    }
  }
  return false;
}

String phoneVerificationRequiredMessage(AppLocalizations? loc) {
  return loc?.phoneVerificationRequiredMessage ??
      'Verify your phone number in Profile before continuing.';
}

/// Returns true when the user is verified (or becomes verified in-dialog).
Future<bool> ensurePhoneVerifiedForAction(BuildContext context) async {
  final auth = context.read<AuthService>();
  if (auth.isUserVerified) return true;

  final loc = AppLocalizations.of(context);
  final phone = (auth.currentUser?['phone_number'] ?? '').toString().trim();
  if (phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          phoneVerificationRequiredMessage(loc),
        ),
        action: SnackBarAction(
          label: loc?.verifyPhoneAction ?? 'Verify phone',
          onPressed: () => Navigator.pushNamed(context, '/profile'),
        ),
      ),
    );
    return false;
  }

  return showPhoneVerificationDialog(context, phone: phone, auth: auth);
}

Future<bool> showPhoneVerificationDialog(
  BuildContext context, {
  required String phone,
  required AuthService auth,
}) async {
  final codeController = TextEditingController();
  var codeSent = false;
  var verified = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final locDialog = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(locDialog.verifyPhoneDialogTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(locDialog.verifyPhoneDialogMessage(phone)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: locDialog.sixDigitCodeLabel,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(locDialog.cancelAction),
              ),
              if (!codeSent)
                FilledButton(
                  onPressed: () async {
                    try {
                      await ApiService.sendPhoneVerificationCode(phone);
                      if (!ctx2.mounted) return;
                      setDialogState(() => codeSent = true);
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(
                          content: Text(locDialog.codeSentEnterAbove),
                        ),
                      );
                    } catch (e) {
                      if (!ctx2.mounted) return;
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(
                          content: Text(
                            userErrorText(
                              ctx2,
                              e,
                              fallback: locDialog.errorTitle,
                            ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Text(locDialog.sendCodeButton),
                ),
              FilledButton(
                onPressed: () async {
                  final code = codeController.text.trim();
                  if (code.length != 6) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(
                        content: Text(locDialog.pleaseEnter6DigitCode),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  try {
                    await ApiService.verifyPhone(phone, code);
                    await auth.refreshProfile();
                    if (!ctx2.mounted) return;
                    verified = true;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(
                        content: Text(locDialog.phoneVerifiedSuccess),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!ctx2.mounted) return;
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(
                        content: Text(
                          userErrorText(
                            ctx2,
                            e,
                            fallback: locDialog.errorTitle,
                          ),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(locDialog.verifyButton),
              ),
            ],
          );
        },
      );
    },
  );

  codeController.dispose();
  return verified || auth.isUserVerified;
}

void showPhoneVerificationRequiredSnackBar(BuildContext context) {
  final loc = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(phoneVerificationRequiredMessage(loc)),
      action: SnackBarAction(
        label: loc?.verifyPhoneAction ?? 'Verify phone',
        onPressed: () {
          final auth = context.read<AuthService>();
          final phone =
              (auth.currentUser?['phone_number'] ?? '').toString().trim();
          if (phone.isEmpty) {
            Navigator.pushNamed(context, '/profile');
            return;
          }
          showPhoneVerificationDialog(context, phone: phone, auth: auth);
        },
      ),
    ),
  );
}
