part of 'production_auth_pages.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  bool _sendingOtp = false;
  bool _otpSent = false;
  String _authType = 'password';
  String? _devOtp;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _formattedPhone() => '+964${_phoneController.text.trim()}';

  bool _isAccountNotFound(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 404) return true;
      final code = e.body?['code']?.toString();
      if (code == 'account_not_found') return true;
    }
    return false;
  }

  Future<void> _showAccountNotFoundDialog() async {
    final loc = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.errorTitle),
        content: Text(
          trLegacyText(
            context,
            'No account found with this phone number. Please create an account first.',
            ar: 'لا يوجد حساب بهذا الرقم. يرجى إنشاء حساب أولاً.',
            ku: 'هیچ هەژمارێک بەم ژمارەیە نەدۆزرایەوە. تکایە سەرەتا هەژمار دروست بکە.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.okAction),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/signup');
            },
            child: Text(loc.createAccount),
          ),
        ],
      ),
    );
  }

  Future<void> _showApiErrorDialog(ApiException e) async {
    if (_isAccountNotFound(e)) {
      await _showAccountNotFoundDialog();
      return;
    }
    String msg = e.message;
    if (e.statusCode == 429) {
      final retryAfter = e.body?['retry_after'];
      final seconds = retryAfter is int
          ? retryAfter
          : (retryAfter is num ? retryAfter.toInt() : null);
      if (seconds != null && seconds > 0) {
        final minutes = (seconds / 60).ceil();
        msg = '$msg Try again in $minutes minute${minutes == 1 ? '' : 's'}.';
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.errorTitle),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.okAction),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(AppLocalizations.of(context)!.enterPhoneNumber),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _sendingOtp = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final resp = await authService.sendPhoneLoginCode(_formattedPhone());
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _devOtp = (resp['dev_code'] ?? '').toString();
        if (_devOtp != null && _devOtp!.isEmpty) _devOtp = null;
      });
      if (_devOtp != null && kDebugMode) {
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
    } on ApiException catch (e) {
      if (!mounted) return;
      await _showApiErrorDialog(e);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage.sendOtp');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.otpFailed,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
        });
      }
    }
  }

  Future<void> _loginWithPhone() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.loginWithPhoneOtp(
        _formattedPhone(),
        _otpController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage.phoneOtp');
      if (_isAccountNotFound(e)) {
        await _showAccountNotFoundDialog();
        return;
      }
      if (e is ApiException) {
        await _showApiErrorDialog(e);
        return;
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isPhoneAuth = _authType == 'phone';

    return Scaffold(
      appBar: AppBar(title: Text(loc.loginTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                trLegacyText(
                  context,
                  'Sign in with:',
                  ar: 'تسجيل الدخول باستخدام:',
                  ku: 'چوونەژوورەوە بە:',
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _authType,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _authType = value;
                    _otpSent = false;
                    _otpController.clear();
                    _devOtp = null;
                  });
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(loc.passwordLabel),
                        value: 'password',
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(loc.phoneLabel),
                        value: 'phone',
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!isPhoneAuth) ...[
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: loc.emailOrPhoneLabel,
                    hintText: loc.enterEmailOrPhoneHint,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.emailOrPhoneRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc.passwordLabel,
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? loc.requiredField
                      : null,
                ),
              ] else ...[
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: loc.enterPhoneNumber,
                    hintText: '7XX XXX XXXX',
                    prefixText: '+964 ',
                  ),
                  inputFormatters: [
                    services.FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9]'),
                    ),
                    services.LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.requiredField
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: loc.sixDigitCodeLabel,
                        ),
                        inputFormatters: [
                          services.FilteringTextInputFormatter.digitsOnly,
                          services.LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (v) => (!_otpSent)
                            ? loc.sendCodeFirst
                            : ((v == null || v.trim().length != 6)
                                  ? loc.requiredField
                                  : null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: (_loading || _sendingOtp) ? null : _sendOtp,
                      child: _sendingOtp
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_otpSent ? loc.resend : loc.sendCode),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Semantics(
                button: true,
                label: loc.navLogin,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : (isPhoneAuth ? _loginWithPhone : _login),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.navLogin),
                ),
              ),
              if (!isPhoneAuth)
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/forgot-password'),
                  child: Text(loc.forgotPasswordLink),
                ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(loc.createAccount),
              ),
            ],
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 3,
        onTap: (idx) {
          switch (idx) {
            case 0:
              navigateMainShellTab(context, '/');
              break;
            case 1:
              navigateMainShellTab(context, '/favorites');
              break;
            case 2:
              navigateMainShellTab(context, '/dealers');
              break;
            case 3:
              break;
          }
        },
      ),
    );
  }
}
