part of 'production_auth_pages.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialDealerMode = false});

  final bool initialDealerMode;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  bool _sendingOtp = false;
  bool _otpSent = false;
  late bool _isDealer;
  bool _pendingNewDealerAccount = false;
  String? _devOtp;

  @override
  void initState() {
    super.initState();
    _isDealer = widget.initialDealerMode;
  }

  @override
  void dispose() {
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

  bool _isPersonalAccountConflict(Object e) {
    if (e is ApiException) {
      final code = e.body?['code']?.toString();
      if (code == 'personal_account_exists') return true;
    }
    return false;
  }

  bool _isDealerAccountConflict(Object e) {
    if (e is ApiException) {
      final code = e.body?['code']?.toString();
      if (code == 'dealer_account_exists') return true;
    }
    return false;
  }

  Future<void> _showPersonalAccountConflictDialog() async {
    final loc = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.errorTitle),
        content: Text(
          trLegacyText(
            context,
            'This phone number is registered to a personal account. Please use personal login instead.',
            ar: 'رقم الهاتف هذا مسجل لحساب شخصي. يرجى استخدام تسجيل الدخول الشخصي.',
            ku: 'ئەم ژمارەی تەلەفۆنە بۆ هەژمارێکی کەسی تۆمارکراوە. تکایە چوونەژوورەوەی کەسی بەکاربهێنە.',
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
              _setAccountType(false);
            },
            child: Text(loc.personalAccountLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showDealerAccountConflictDialog() async {
    final loc = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.errorTitle),
        content: Text(
          trLegacyText(
            context,
            'This phone number is registered to a dealer account. Please use dealer login instead.',
            ar: 'رقم الهاتف هذا مسجل لحساب وكيل. يرجى استخدام تسجيل دخول الوكيل.',
            ku: 'ئەم ژمارەی تەلەفۆنە بۆ هەژمارێکی وەکیل تۆمارکراوە. تکایە چوونەژوورەوەی وەکیل بەکاربهێنە.',
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
              _setAccountType(true);
            },
            child: Text(loc.dealerFallbackLabel),
          ),
        ],
      ),
    );
  }

  void _resetOtpState() {
    _otpSent = false;
    _otpController.clear();
    _devOtp = null;
    _pendingNewDealerAccount = false;
  }

  void _setAccountType(bool isDealer) {
    if (_isDealer == isDealer) return;
    setState(() {
      _isDealer = isDealer;
      _resetOtpState();
    });
  }

  Future<void> _showApiErrorDialog(ApiException e) async {
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
      final dealerPurpose = _isDealer ? 'dealer' : null;
      Map<String, dynamic> resp;
      if (_isDealer) {
        try {
          resp = await authService.sendPhoneLoginCode(
            _formattedPhone(),
            createIfMissing: false,
            purpose: dealerPurpose,
          );
          _pendingNewDealerAccount = false;
        } on ApiException catch (e) {
          if (_isPersonalAccountConflict(e)) {
            if (!mounted) return;
            _resetOtpState();
            await _showPersonalAccountConflictDialog();
            return;
          }
          if (!_isAccountNotFound(e)) rethrow;
          resp = await authService.sendPhoneLoginCode(
            _formattedPhone(),
            purpose: dealerPurpose,
          );
          _pendingNewDealerAccount = true;
        }
      } else {
        try {
          resp = await authService.sendPhoneLoginCode(_formattedPhone());
          _pendingNewDealerAccount = false;
        } on ApiException catch (e) {
          if (_isDealerAccountConflict(e)) {
            if (!mounted) return;
            _resetOtpState();
            await _showDealerAccountConflictDialog();
            return;
          }
          rethrow;
        }
      }
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
      if (_isPersonalAccountConflict(e)) {
        _resetOtpState();
        await _showPersonalAccountConflictDialog();
        return;
      }
      if (_isDealerAccountConflict(e)) {
        _resetOtpState();
        await _showDealerAccountConflictDialog();
        return;
      }
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
      final dealerPurpose = _isDealer ? 'dealer' : null;
      final response = await authService.loginWithPhoneOtp(
        _formattedPhone(),
        _otpController.text.trim(),
        purpose: dealerPurpose,
      );
      if (!mounted) return;

      if (_isDealer &&
          !_pendingNewDealerAccount &&
          !AuthService.isDealerAccount(AuthService.userMapFrom(response['user']))) {
        await authService.logout();
        _resetOtpState();
        await _showPersonalAccountConflictDialog();
        return;
      }

      if (!_isDealer &&
          AuthService.isDealerAccount(AuthService.userMapFrom(response['user']))) {
        await authService.logout();
        _resetOtpState();
        await _showDealerAccountConflictDialog();
        return;
      }

      if (_isDealer && _pendingNewDealerAccount) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/dealer-onboarding',
          (route) => false,
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage.phoneOtp');
      if (e is ApiException) {
        if (_isPersonalAccountConflict(e)) {
          _resetOtpState();
          await _showPersonalAccountConflictDialog();
          return;
        }
        if (_isDealerAccountConflict(e)) {
          _resetOtpState();
          await _showDealerAccountConflictDialog();
          return;
        }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isDealer
              ? trLegacyText(
                  context,
                  'Dealer account',
                  ar: 'حساب الوكالة',
                  ku: 'هەژماری ناوەندی فرۆشتن',
                )
              : loc.loginTitle,
        ),
      ),
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
                  'Account type',
                  ar: 'نوع الحساب',
                  ku: 'جۆری هەژمار',
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _isDealer ? 'dealer' : 'personal',
                onChanged: (value) {
                  if (value == null) return;
                  _setAccountType(value == 'dealer');
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(loc.personalAccountLabel),
                        value: 'personal',
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(loc.dealerFallbackLabel),
                        value: 'dealer',
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                trLegacyText(
                  context,
                  'Enter your phone number to log in or create an account.',
                  ar: 'أدخل رقم هاتفك لتسجيل الدخول أو إنشاء حساب.',
                  ku: 'ژمارەی تەلەفۆنەکەت بنووسە بۆ چوونەژوورەوە یان دروستکردنی هەژمار.',
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
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
                onChanged: (_) => _resetOtpState(),
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
              const SizedBox(height: 20),
              Semantics(
                button: true,
                label: loc.navLogin,
                child: ElevatedButton(
                  onPressed: _loading ? null : _loginWithPhone,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.navLogin),
                ),
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
