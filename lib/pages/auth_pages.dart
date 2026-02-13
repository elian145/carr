import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
// Removed unused imports
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../widgets/theme_toggle_widget.dart';

// Lightweight i18n helpers for auth pages
String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;
String _forgotPasswordTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'نسيت كلمة المرور';
  if (c == 'ku') return 'وشەی نهێنیم لەبیر چووە';
  return 'Forgot Password';
}

String _welcomeBackText(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'مرحبًا بعودتك';
  if (c == 'ku') return 'بەخێربێیتەوە';
  return 'Welcome Back';
}

String _usernameOrEmailLabel(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return '${loc.usernameLabel} / ${loc.emailLabel}';
}

String _pleaseEnterUsernameOrEmail(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال اسم المستخدم أو البريد الإلكتروني';
  if (c == 'ku') return 'تکایە ناوی بەکارهێنەر یان ئیمەیڵ بنووسە';
  return 'Please enter your username or email';
}

String _pleaseEnterPassword(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال كلمة المرور';
  if (c == 'ku') return 'تکایە وشەی نهێنی بنووسە';
  return 'Please enter your password';
}

String _loginFailedText(BuildContext context, String message) {
  final c = _lang(context);
  final isServerError = message.contains('500') || message.contains('502') || message.contains('ProxyNotConfigured');
  final hint = isServerError
      ? ' Make sure the listings server (port 5000) and proxy (5003) are running.'
      : '';
  if (c == 'ar') return 'فشل تسجيل الدخول: $message$hint';
  if (c == 'ku') return 'هەڵە لە چوونەژوورەوە: $message$hint';
  return 'Login failed: $message$hint';
}

String _forgotPasswordQuestion(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'هل نسيت كلمة المرور؟';
  if (c == 'ku') return 'وشەی نهێنیت بیرچووە؟';
  return 'Forgot Password?';
}

String _dontHaveAccount(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'ليس لديك حساب؟ ';
  if (c == 'ku') return 'هەژمارت نیە؟ ';
  return "Don't have an account? ";
}

String _alreadyHaveAccount(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'لديك حساب؟ ';
  if (c == 'ku') return 'هەژمارت هەیە؟ ';
  return 'Already have an account? ';
}

// Removed unused helper _createAccountTitle
String _firstNameLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'الاسم الأول';
  if (c == 'ku') return 'ناوی یەکەم';
  return 'First Name';
}

String _lastNameLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'اسم العائلة';
  if (c == 'ku') return 'ناوی دووەم';
  return 'Last Name';
}

String _pleaseEnterFirstName(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال الاسم الأول';
  if (c == 'ku') return 'تکایە ناوی یەکەم بنووسە';
  return 'Please enter your first name';
}

String _pleaseEnterLastName(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال اسم العائلة';
  if (c == 'ku') return 'تکایە ناوی دووەم بنووسە';
  return 'Please enter your last name';
}

String _usernameMustBeAtLeast3(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يجب أن يكون اسم المستخدم 3 أحرف على الأقل';
  if (c == 'ku') return 'ناوی بەکارهێنەر پێویستە کەمەترین ٣ پیت بێت';
  return 'Username must be at least 3 characters';
}

String _pleaseEnterValidEmail(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى إدخال بريد إلكتروني صالح';
  if (c == 'ku') return 'تکایە ئیمەیلێکی دروست بنووسە';
  return 'Please enter a valid email';
}

String _phoneOptionalLabel(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  final c = _lang(context);
  if (c == 'ar') return '${loc.phoneLabel} (اختياري)';
  if (c == 'ku') return '${loc.phoneLabel} (هەلبژاردە)';
  return 'Phone Number (Optional)';
}

String _confirmPasswordLabel(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'تأكيد كلمة المرور';
  if (c == 'ku') return 'دووبارە کردنەوەی وشەی نهێنی';
  return 'Confirm Password';
}

String _pleaseConfirmPassword(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'يرجى تأكيد كلمة المرور';
  if (c == 'ku') return 'تکایە وشەی نهێنی دووبارە بنووسە';
  return 'Please confirm your password';
}

String _passwordsDoNotMatch(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'كلمتا المرور غير متطابقتين';
  if (c == 'ku') return 'پاسۆردەکان یەک ناگرن';
  return 'Passwords do not match';
}

String _sendResetLink(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'إرسال رابط إعادة التعيين';
  if (c == 'ku') return 'ناردنی بەستەری ڕێکخستنەوە';
  return 'Send Reset Link';
}

String _backToLogin(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'العودة إلى تسجيل الدخول';
  if (c == 'ku') return 'گەڕانەوە بۆ چوونەژوورەوە';
  return 'Back to Login';
}

String _backText(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'رجوع';
  if (c == 'ku') return 'گەڕانەوە';
  return 'Back';
}

String _checkYourEmailTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'تحقق من بريدك الإلكتروني';
  if (c == 'ku') return 'پشکنینی ئیمەیڵەکەت بکە';
  return 'Check Your Email';
}

String _resetPasswordTitle(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') return 'إعادة تعيين كلمة المرور';
  if (c == 'ku') return 'ڕێکخستنی وشەی نهێنی';
  return 'Reset Password';
}

String _resetEmailSent(BuildContext context, String email) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'أرسلنا رابط إعادة تعيين إلى $email. يرجى التحقق من بريدك.';
  }
  if (c == 'ku') {
    return 'بەستەری ڕێکخستنەوە نێردرا بۆ $email . تکایە ئیمەیلەکەت بپشکنە.';
  }
  return "We've sent a password reset link to $email. Please check your email and follow the instructions.";
}

String _registrationSuccess(BuildContext context) {
  final c = _lang(context);
  if (c == 'ar') {
    return 'تم التسجيل بنجاح! يرجى التحقق من بريدك الإلكتروني للتفعيل.';
  }
  if (c == 'ku') {
    return 'خۆتۆمارکردن سەرکەوتوو بوو! تکایە ئیمەیڵەکەت بپشکنە بۆ پشتڕاستکردن.';
  }
  return 'Registration successful! Please check your email for verification.';
}

String _registrationFailed(BuildContext context, String msg) {
  final c = _lang(context);
  if (c == 'ar') return 'فشل التسجيل: $msg';
  if (c == 'ku') return 'هەڵە لە خۆتۆمارکردن: $msg';
  return 'Registration failed: $msg';
}

String _failedToSendResetEmail(BuildContext context, String msg) {
  final c = _lang(context);
  if (c == 'ar') return 'فشل إرسال بريد الاستعادة: $msg';
  if (c == 'ku') return 'نەتوانرا ئیمەیلی ڕێکخستنەوە بنێردرێت: $msg';
  return 'Failed to send reset email: $msg';
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loginFailedText(context, e.toString())),
            backgroundColor: Colors.red,
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
        title: Text(AppLocalizations.of(context)!.loginTitle),
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
                Icons.directions_car,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                _welcomeBackText(context),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: _usernameOrEmailLabel(context),
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _pleaseEnterUsernameOrEmail(context);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _pleaseEnterPassword(context);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(AppLocalizations.of(context)!.loginAction),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/forgot-password');
                },
                child: Text(_forgotPasswordQuestion(context)),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_dontHaveAccount(context)),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/register');
                    },
                    child: Text(AppLocalizations.of(context)!.createAccount),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isSendingOtp = false;
  String? _devOtp;
  bool _otpSent = false;
  String _authType = 'email'; // 'email' | 'phone'

  @override
  void dispose() {
    _otpController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _hasPassword() => _passwordController.text.trim().isNotEmpty;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the highlighted fields'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_authType == 'phone') {
        final res = await ApiService.phoneVerify(
          phoneNumber: _phoneController.text.trim(),
          code: _otpController.text.trim(),
          username: _usernameController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _hasPassword() ? _passwordController.text : null,
        );
        // Load profile + connect websocket
        await authService.initialize();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Signed in'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacementNamed(context, '/');
      } else {
        await authService.register(
          username: _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          phoneNumber: _phoneController.text.isNotEmpty
              ? _phoneController.text
              : null,
        );
        await authService.initialize();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_registrationSuccess(context)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_registrationFailed(context, e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_phoneOptionalLabel(context))));
      return;
    }
    setState(() => _isSendingOtp = true);
    try {
      final resp = await ApiService.phoneStart(
        phoneNumber: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _hasPassword() ? _passwordController.text : null,
      );
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _devOtp = (resp['dev_code'] ?? '').toString();
      });
      if (_devOtp != null && _devOtp!.isNotEmpty && kDebugMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.devOtpCode(_devOtp!)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.otpSent)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.otpFailedWithMsg(e.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.createAccount),
        actions: const [ThemeToggleWidget()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(
                Icons.directions_car,
                size: 60,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.createAccount,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Authentication Type Selection
              Text(
                AppLocalizations.of(context)!.chooseAuthMethodTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text(AppLocalizations.of(context)!.emailLabel),
                      value: 'email',
                      groupValue: _authType,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _authType = v;
                          _otpSent = false;
                          _otpController.clear();
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text(AppLocalizations.of(context)!.phoneLabel),
                      value: 'phone',
                      groupValue: _authType,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _authType = v;
                          _otpSent = false;
                          _otpController.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: _firstNameLabel(context),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _pleaseEnterFirstName(context);
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: _lastNameLabel(context),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _pleaseEnterLastName(context);
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.usernameLabel,
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)!.requiredField;
                  }
                  if (value.length < 3) {
                    return _usernameMustBeAtLeast3(context);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailLabel,
                  prefixIcon: const Icon(Icons.email),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (_authType == 'phone') {
                    // optional in phone OTP mode
                    return null;
                  }
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
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: _phoneOptionalLabel(context),
                  prefixIcon: const Icon(Icons.phone),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                validator: (value) {
                  if (_authType != 'phone') return null;
                  if (value == null || value.trim().isEmpty) {
                    return AppLocalizations.of(context)!.requiredField;
                  }
                  return null;
                },
              ),
              if (_authType == 'phone') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isSendingOtp ? null : _sendOtp,
                    icon: const Icon(Icons.sms),
                    label: Text(
                      _isSendingOtp ? '...' : AppLocalizations.of(context)!.sendOtp,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.sendCode,
                    prefixIcon: const Icon(Icons.password),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (value) {
                    if (_authType != 'phone') return null;
                    if (!_otpSent) return AppLocalizations.of(context)!.sendCodeFirst;
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!.requiredField;
                    }
                    if (value.trim().length != 6) {
                      return AppLocalizations.of(context)!.requiredField;
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  // Optional password for phone OTP mode (passwordless auth).
                  if (_authType == 'phone' && (value == null || value.isEmpty)) {
                    return null;
                  }
                  if (value == null || value.isEmpty) return _pleaseEnterPassword(context);
                  if (value.length < 8) {
                    return AppLocalizations.of(context)!.passwordMin8;
                  }
                  // Keep client-side validation aligned with backend `kk.auth.validate_password`
                  if (!RegExp(r'[A-Z]').hasMatch(value)) {
                    return 'Password must contain at least one uppercase letter';
                  }
                  if (!RegExp(r'[a-z]').hasMatch(value)) {
                    return 'Password must contain at least one lowercase letter';
                  }
                  if (!RegExp(r'\d').hasMatch(value)) {
                    return 'Password must contain at least one number';
                  }
                  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
                    return 'Password must contain at least one special character';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: _confirmPasswordLabel(context),
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      );
                    },
                  ),
                ),
                validator: (value) {
                  final pw = _passwordController.text;
                  // In phone OTP mode, confirm is only required if password is provided.
                  if (_authType == 'phone' && pw.trim().isEmpty) return null;
                  if (value == null || value.isEmpty) return _pleaseConfirmPassword(context);
                  if (value != pw) return _passwordsDoNotMatch(context);
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(AppLocalizations.of(context)!.createAccount),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_alreadyHaveAccount(context)),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: Text(AppLocalizations.of(context)!.loginAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.forgotPassword(_emailController.text);

      if (!mounted) return;
      setState(() => _emailSent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_failedToSendResetEmail(context, e.toString())),
            backgroundColor: Colors.red,
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
                    ? _checkYourEmailTitle(context)
                    : _resetPasswordTitle(context),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _emailSent
                    ? _resetEmailSent(context, _emailController.text)
                    : AppLocalizations.of(context)!.sendCodeFirst,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              if (!_emailSent) ...[
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
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendResetEmail,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(_sendResetLink(context)),
                ),
              ] else ...[
                ElevatedButton(
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
