part of 'edit_dealer_page.dart';

mixin _EditDealerPagePhoneVerification on _EditDealerPageMedia {
  bool _isDealerPhoneVerified(String value) {
    final normalized = normalizeDealerPhoneForVerification(value);
    return normalized.isNotEmpty && _verifiedPhones.contains(normalized);
  }

  Future<void> _verifyDealerPhoneAt(int index) async {
    if (_saving || index < 0 || index >= _phones.length) return;
    final phone = _phones[index].text.trim();
    final normalized = normalizeDealerPhoneForVerification(phone);
    if (normalized.length != 10 && normalized.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Enter a valid phone number first.',
              ar: 'أدخل رقم هاتف صالحاً أولاً.',
              ku: 'سەرەتا ژمارەیەکی تەلەفۆنی دروست بنووسە.',
            ),
          ),
        ),
      );
      return;
    }

    final codeController = TextEditingController();
    var codeSent = false;
    var sending = false;
    var verifying = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> sendCode() async {
            if (sending) return;
            setDialogState(() => sending = true);
            try {
              final response = await ApiService.sendDealerPhoneVerification(
                phone,
              );
              if (!dialogContext.mounted) return;
              if (response['verified'] == true) {
                Navigator.pop(dialogContext, true);
                return;
              }
              setDialogState(() => codeSent = true);
              final devCode = (response['dev_code'] ?? '').toString().trim();
              if (kDebugMode && devCode.isNotEmpty) {
                codeController.text = devCode;
              }
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _tr(
                      'Verification code sent.',
                      ar: 'تم إرسال رمز التحقق.',
                      ku: 'کۆدی پشتڕاستکردنەوە نێردرا.',
                    ),
                  ),
                ),
              );
            } catch (error) {
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    userErrorText(
                      dialogContext,
                      error,
                      fallback: _tr(
                        'Could not send the code.',
                        ar: 'تعذر إرسال الرمز.',
                        ku: 'نەتوانرا کۆدەکە بنێردرێت.',
                      ),
                    ),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => sending = false);
              }
            }
          }

          Future<void> verifyCode() async {
            final code = codeController.text.trim();
            if (!codeSent || code.length != 6) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    _tr(
                      'Send the code and enter all 6 digits.',
                      ar: 'أرسل الرمز وأدخل الأرقام الستة.',
                      ku: 'کۆدەکە بنێرە و هەموو ٦ ژمارەکە بنووسە.',
                    ),
                  ),
                ),
              );
              return;
            }
            setDialogState(() => verifying = true);
            try {
              await ApiService.verifyDealerPhone(phone, code);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, true);
            } catch (error) {
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    userErrorText(
                      dialogContext,
                      error,
                      fallback: _tr(
                        'The code is invalid or expired.',
                        ar: 'الرمز غير صالح أو منتهي الصلاحية.',
                        ku: 'کۆدەکە هەڵەیە یان بەسەرچووە.',
                      ),
                    ),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => verifying = false);
              }
            }
          }

          return AlertDialog(
            title: Text(
              _tr(
                'Verify dealership phone',
                ar: 'التحقق من هاتف الوكالة',
                ku: 'پشتڕاستکردنەوەی تەلەفۆنی ناوەند',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    'We will send a verification code to $phone. This number cannot be saved until it is verified.',
                    ar: 'سنرسل رمز تحقق إلى $phone. لا يمكن حفظ هذا الرقم حتى يتم التحقق منه.',
                    ku: 'کۆدی پشتڕاستکردنەوە بۆ $phone دەنێرین. تا پشتڕاست نەکرێتەوە ناتوانرێت پاشەکەوت بکرێت.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: _tr(
                      '6-digit code',
                      ar: 'رمز من 6 أرقام',
                      ku: 'کۆدی ٦ ژمارەیی',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending || verifying
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(_loc?.cancelAction ?? 'Cancel'),
              ),
              TextButton(
                onPressed: sending || verifying ? null : sendCode,
                child: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        codeSent
                            ? _tr(
                                'Resend code',
                                ar: 'إعادة إرسال الرمز',
                                ku: 'کۆدەکە دووبارە بنێرە',
                              )
                            : _tr(
                                'Send code',
                                ar: 'إرسال الرمز',
                                ku: 'کۆد بنێرە',
                              ),
                      ),
              ),
              FilledButton(
                onPressed: sending || verifying ? null : verifyCode,
                child: verifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_tr('Verify', ar: 'تحقق', ku: 'پشتڕاستکردنەوە')),
              ),
            ],
          );
        },
      ),
    );
    codeController.dispose();
    if (verified == true && mounted) {
      setState(() => _verifiedPhones.add(normalized));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Phone number verified.',
              ar: 'تم التحقق من رقم الهاتف.',
              ku: 'ژمارەی تەلەفۆن پشتڕاستکرایەوە.',
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
