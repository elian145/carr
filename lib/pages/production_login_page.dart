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
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();
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
    _phoneFocus.dispose();
    _otpFocus.dispose();
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
          AppLocalizations.of(context)!.thisPhoneNumberIsRegisteredToAPersonalAccountPleaseUsePersonalLoginInste,
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
          AppLocalizations.of(context)!.thisPhoneNumberIsRegisteredToADealerAccountPleaseUseDealerLoginInstead,
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

  Future<void> _showApiErrorDialog(
    ApiException e, {
    String? fallback,
  }) async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    // ApiService already appends retry timing for 429 responses.
    final msg = userErrorText(
      context,
      e,
      fallback: fallback ?? loc.errorTitle,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.errorTitle),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.okAction),
          ),
        ],
      ),
    );
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    // Iraqi mobile numbers are 10 digits (7XX XXX XXXX) after the +964 prefix.
    if (phone.length != 10) {
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
      requestFocusAfterFrame(_otpFocus);
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
      await _showApiErrorDialog(
        e,
        fallback: AppLocalizations.of(context)!.otpFailed,
      );
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

  InputDecoration _loginFieldDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? prefixText,
    Widget? prefixIcon,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fill = isLight ? const Color(0xFFF4F4F4) : Colors.white.withValues(alpha: 0.08);
    final muted = isLight ? const Color(0xFF757575) : Colors.white70;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
      hintStyle: TextStyle(color: muted),
      prefixStyle: const TextStyle(
        color: AppColors.brandOrange,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isLight ? const Color(0xFFE0E0E0) : Colors.white24,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: 2,
        ),
      ),
    );
  }

  Widget _accountTypeCard({
    required BuildContext context,
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = selected
        ? AppColors.brandOrange
        : (isLight ? const Color(0xFFE0E0E0) : Colors.white24);
    final fill = selected
        ? AppColors.brandOrange.withValues(alpha: isLight ? 0.10 : 0.18)
        : (isLight ? Colors.white : Colors.white.withValues(alpha: 0.06));
    final ink = selected
        ? AppColors.brandOrange
        : (isLight ? const Color(0xFF424242) : Colors.white70);

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: ink, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalConsentLine(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    String tr(String en, String ar, String ku) {
      if (code == 'ar') return ar;
      if (code == 'ku' || code == 'ckb') return ku;
      return en;
    }

    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final linkStyle = baseStyle.copyWith(
      color: AppColors.brandOrange,
      fontWeight: FontWeight.w600,
    );

    Future<void> openLegal(LegalDocument doc) async {
      final cfg = await TrustConfig.load();
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LegalDocumentPage(
            document: doc,
            externalUrl:
                doc == LegalDocument.terms ? cfg.termsUrl : cfg.privacyUrl,
          ),
        ),
      );
    }

    Widget link(String label, LegalDocument doc) => GestureDetector(
          onTap: () => openLegal(doc),
          child: Text(label, style: linkStyle),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          tr(
            'By continuing, you agree to our ',
            'بالمتابعة، فإنك توافق على ',
            'بە بەردەوامبوون، تۆ ڕازی دەبیت بە ',
          ),
          style: baseStyle,
        ),
        link(tr('Terms', 'شروط الخدمة', 'مەرجەکان'), LegalDocument.terms),
        Text(tr(' and ', ' و ', ' و '), style: baseStyle),
        link(
          tr('Privacy Policy', 'سياسة الخصوصية', 'سیاسەتی تایبەتمەندی'),
          LegalDocument.privacy,
        ),
        Text('.', style: baseStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final primaryInk = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final secondaryInk = isLight ? const Color(0xFF757575) : Colors.white70;
    final cardFill = isLight
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.085),
            AppThemes.darkHomeShellBackground,
          );
    final cardBorder =
        isLight ? const Color(0xFFE0E0E0) : Colors.white.withValues(alpha: 0.12);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(loc.loginTitle),
        elevation: 0,
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: AppThemes.shellBackgroundDecoration(
          Theme.of(context).brightness,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppResponsive.pagePadding(context).left,
            20,
            AppResponsive.pagePadding(context).right,
            120,
          ),
          child: AppResponsive.constrainContent(
            Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isLight ? 0.06 : 0.35,
                        ),
                        blurRadius: isLight ? 16 : 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.brandOrange
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone_iphone_rounded,
                            color: AppColors.brandOrange,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.welcomeBack,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: primaryInk,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.enterYourPhoneNumberToLogInOrCreateAnAccount,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: secondaryInk,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        AppLocalizations.of(context)!.accountType,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: secondaryInk,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _accountTypeCard(
                              context: context,
                              selected: !_isDealer,
                              icon: Icons.person_outline_rounded,
                              label: loc.personalAccountLabel,
                              onTap: () => _setAccountType(false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _accountTypeCard(
                              context: context,
                              selected: _isDealer,
                              icon: Icons.storefront_outlined,
                              label: loc.dealerFallbackLabel,
                              onTap: () => _setAccountType(true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) {
                          if (_otpSent) {
                            _otpFocus.requestFocus();
                          } else {
                            _sendOtp();
                          }
                        },
                        style: TextStyle(
                          color: primaryInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        decoration: _loginFieldDecoration(
                          context,
                          labelText: loc.enterPhoneNumber,
                          hintText: '7XX XXX XXXX',
                          prefixText: '+964 ',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            color: AppColors.brandOrange,
                          ),
                        ),
                        inputFormatters: [
                          services.FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9]'),
                          ),
                          services.LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          final digits = (v ?? '').trim();
                          if (digits.isEmpty) return loc.requiredField;
                          if (digits.length != 10) return loc.enterPhoneNumber;
                          return null;
                        },
                        onChanged: (_) => _resetOtpState(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _otpController,
                              focusNode: _otpFocus,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (_otpSent && !_loading) {
                                  _loginWithPhone();
                                }
                              },
                              style: TextStyle(
                                color: primaryInk,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                letterSpacing: 2,
                              ),
                              decoration: _loginFieldDecoration(
                                context,
                                labelText: loc.sixDigitCodeLabel,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: AppColors.brandOrange,
                                ),
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
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed:
                                  (_loading || _sendingOtp) ? null : _sendOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandOrange,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.brandOrange
                                    .withValues(alpha: 0.45),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _sendingOtp
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _otpSent ? loc.resend : loc.sendCode,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Semantics(
                        button: true,
                        label: loc.navLogin,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _loginWithPhone,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandOrange,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.brandOrange
                                  .withValues(alpha: 0.45),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    loc.navLogin,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLegalConsentLine(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
              navigateMainShellTab(context, '/sell');
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
