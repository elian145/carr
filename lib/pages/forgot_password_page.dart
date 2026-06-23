import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../widgets/theme_toggle_widget.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  /// `'email'` or `'phone'`.
  String _recoveryMethod = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _forgotPasswordTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Forgot Password',
      ar: 'نسيت كلمة المرور',
      ku: 'وشەی نهێنیم لەبیر چووە',
    );
  }

  String _resetPasswordTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Reset Password',
      ar: 'إعادة تعيين كلمة المرور',
      ku: 'ڕێکخستنی وشەی نهێنی',
    );
  }

  String _checkYourEmailTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Check Your Email',
      ar: 'تحقق من بريدك الإلكتروني',
      ku: 'پشکنینی ئیمەیڵەکەت بکە',
    );
  }

  String _checkYourPhoneTitle(BuildContext context) {
    return trLegacyText(
      context,
      'Check your messages',
      ar: 'تحقق من رسائلك النصية',
      ku: 'پەیامەکانی SMS بپشکنە',
    );
  }

  String _forgotPasswordIntroEmail(BuildContext context) {
    return trLegacyText(
      context,
      'Enter the email address for your account. We will send a reset code.',
      ar: 'أدخل البريد الإلكتروني المرتبط بحسابك. سنرسل رمز إعادة التعيين.',
      ku: 'ئیمەیڵی هەژمارەکەت بنووسە. کۆدی ڕێکخستنەوە دەنێردرێت.',
    );
  }

  String _forgotPasswordIntroPhone(BuildContext context) {
    return trLegacyText(
      context,
      'Enter the phone number for your account. We will send a reset code by SMS.',
      ar: 'أدخل رقم الهاتف المرتبط بحسابك. سنرسل رمز إعادة التعيين عبر رسالة نصية.',
      ku: 'ژمارەی تەلەفۆنەکەت بنووسە. کۆدەکە بە SMS دەنێردرێت.',
    );
  }

  String _resetEmailSent(BuildContext context, String email) {
    return trLegacyText(
      context,
      "We've sent a password reset link to $email. Please check your email and follow the instructions.",
      ar: 'أرسلنا رابط إعادة تعيين إلى $email. يرجى التحقق من بريدك.',
      ku: 'بەستەری ڕێکخستنەوە نێردرا بۆ $email . تکایە ئیمەیلەکەت بپشکنە.',
    );
  }

  String _resetSmsSent(BuildContext context, String phone) {
    return trLegacyText(
      context,
      'If an account exists for $phone, we sent a password reset code by SMS.',
      ar: 'إذا وُجد حساب لـ $phone، فقد أرسلنا رمز إعادة التعيين عبر رسالة نصية.',
      ku: 'ئەگەر هەژمارێک هەبێت بۆ $phone، کۆدی ڕێکخستنەوە بە SMS نێردرا.',
    );
  }

  String _checkSpamHint(BuildContext context) {
    return trLegacyText(
      context,
      "If you don't see it, check your spam or junk folder. The link is only sent if an account exists for this email.",
      ar: 'إن لم تجد الرسالة، تحقق من مجلد البريد العشوائي. يُرسل الرابط فقط إذا وُجد حساب لهذا البريد.',
      ku: 'ئەگەر نەت بینی، پشکنینی سپام بکە. بەستەرەکە تەنها ئەگەر هەژمارێک بۆ ئەم ئیمەیڵە هەبێت نێردرێت.',
    );
  }

  String _smsResetHint(BuildContext context) {
    return trLegacyText(
      context,
      'SMS may take a minute or two. A code is only sent if an account exists for this number.',
      ar: 'قد يستغرق وصول الرسالة دقيقة أو دقيقتين. يُرسل الرمز فقط إذا وُجد حساب لهذا الرقم.',
      ku: 'ڕەنگە SMS کەمێک دوابکەوێت. کۆدەکە تەنها ئەگەر هەژمارێک بۆ ئەم ژمارەیە هەبێت دەنێردرێت.',
    );
  }

  String _pleaseEnterValidEmail(BuildContext context) {
    return trLegacyText(
      context,
      'Please enter a valid email',
      ar: 'يرجى إدخال بريد إلكتروني صالح',
      ku: 'تکایە ئیمەیلێکی دروست بنووسە',
    );
  }

  String _pleaseEnterValidPhone(BuildContext context) {
    return trLegacyText(
      context,
      'Please enter a valid phone number (at least 8 digits)',
      ar: 'يرجى إدخال رقم هاتف صالح (8 أرقام على الأقل)',
      ku: 'تکایە ژمارەی تەلەفۆنێکی دروست بنووسە (کەمترین ٨ ژمارە)',
    );
  }

  String _sendResetLink(BuildContext context) {
    return trLegacyText(
      context,
      'Send Reset Link',
      ar: 'إرسال رابط إعادة التعيين',
      ku: 'ناردنی بەستەری ڕێکخستنەوە',
    );
  }

  String _sendSmsResetCode(BuildContext context) {
    return trLegacyText(
      context,
      'Send reset code (SMS)',
      ar: 'إرسال رمز إعادة التعيين',
      ku: 'ناردنی کۆدی ڕێکخستنەوە',
    );
  }

  String _enterResetCode(BuildContext context) {
    return trLegacyText(
      context,
      'I have the code – set new password',
      ar: 'أدخل رمز إعادة التعيين',
      ku: 'کۆدی ڕێکخستنەوە بنووسە',
    );
  }

  String _backToLogin(BuildContext context) {
    return trLegacyText(
      context,
      'Back to Login',
      ar: 'العودة إلى تسجيل الدخول',
      ku: 'گەڕانەوە بۆ چوونەژوورەوە',
    );
  }

  String _backText(BuildContext context) {
    return trLegacyText(
      context,
      'Back',
      ar: 'رجوع',
      ku: 'گەڕانەوە',
    );
  }

  String _resetRateLimitedMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Too many reset attempts. Please wait a little and try again.',
      ar: 'تم إرسال طلبات كثيرة جدًا. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.',
      ku: 'زۆر داواکاری نێردراوە. تکایە چەند خولەکێک چاوەڕێ بکە و دووبارە هەوڵبدە.',
    );
  }

  String _failedToSendResetEmailMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Failed to send reset link. Check your email and try again later.',
      ar: 'فشل إرسال رابط إعادة التعيين. تحقق من البريد وحاول لاحقاً.',
      ku: 'نەتوانرا ئیمەییلی ڕێکخستنەوە بنێردرێت. دووبارە هەوڵ بدەرەوە.',
    );
  }

  String _failedToSendSmsResetMessage(BuildContext context) {
    return trLegacyText(
      context,
      'Failed to send SMS. Check the number and try again later.',
      ar: 'تعذر إرسال الرسالة النصية. تحقق من الرقم وحاول لاحقاً.',
      ku: 'نەتوانرا SMS بنێردرێت. ژمارەکە بپشکنە و دووبارە هەوڵ بدەرەوە.',
    );
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_recoveryMethod == 'phone') {
        await authService.forgotPassword(
          _phoneController.text,
          isPhone: true,
        );
      } else {
        await authService.forgotPassword(_emailController.text);
      }

      if (!mounted) return;
      setState(() => _emailSent = true);
    } catch (e, st) {
      logNonFatal(e, st, 'ForgotPasswordPage');
      if (mounted) {
        final message = e is ApiException && e.statusCode == 429
            ? _resetRateLimitedMessage(context)
            : userErrorText(
                context,
                e,
                fallback: _recoveryMethod == 'phone'
                    ? _failedToSendSmsResetMessage(context)
                    : _failedToSendResetEmailMessage(context),
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_forgotPasswordTitle(context)),
        actions: const [ThemeToggleWidget()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.lock_reset,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                _emailSent
                    ? (_recoveryMethod == 'phone'
                          ? _checkYourPhoneTitle(context)
                          : _checkYourEmailTitle(context))
                    : _resetPasswordTitle(context),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _emailSent
                    ? (_recoveryMethod == 'phone'
                          ? _resetSmsSent(context, _phoneController.text)
                          : _resetEmailSent(context, _emailController.text))
                    : (_recoveryMethod == 'phone'
                          ? _forgotPasswordIntroPhone(context)
                          : _forgotPasswordIntroEmail(context)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_emailSent) ...[
                const SizedBox(height: 16),
                Text(
                  _recoveryMethod == 'phone'
                      ? _smsResetHint(context)
                      : _checkSpamHint(context),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 32),
              if (!_emailSent) ...[
                Text(
                  AppLocalizations.of(context)!.chooseAuthMethodTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: _recoveryMethod,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _recoveryMethod = v);
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text(AppLocalizations.of(context)!.emailLabel),
                          value: 'email',
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text(AppLocalizations.of(context)!.phoneLabel),
                          value: 'phone',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_recoveryMethod == 'email')
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.emailLabel,
                      prefixIcon: const Icon(Icons.email),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.of(context)!.emailLabel;
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value)) {
                        return _pleaseEnterValidEmail(context);
                      }
                      return null;
                    },
                  )
                else
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.phoneLabel,
                      hintText:
                          AppLocalizations.of(context)!.useInternationalFormat,
                      prefixIcon: const Icon(Icons.phone),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+\s\-()]+'),
                      ),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLocalizations.of(context)!.requiredField;
                      }
                      final digits = RegExp(
                        r'\d',
                      ).allMatches(value).map((m) => m.group(0)!).join();
                      if (digits.length < 8) {
                        return _pleaseEnterValidPhone(context);
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  label: _recoveryMethod == 'phone'
                      ? _sendSmsResetCode(context)
                      : _sendResetLink(context),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendReset,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(
                            _recoveryMethod == 'phone'
                                ? _sendSmsResetCode(context)
                                : _sendResetLink(context),
                          ),
                  ),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/reset-password');
                  },
                  child: Text(_enterResetCode(context)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text(_backToLogin(context)),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(_backText(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
