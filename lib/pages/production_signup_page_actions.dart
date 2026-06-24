part of 'production_auth_pages.dart';

mixin _SignupPageActions on _SignupPageFields {

  Future<void> _sendOtp() async {
    if (_isDealer) {
      final dn = _dealershipNameController.text.trim();
      final dp = _dealershipPhoneController.text.trim();
      final dl = _dealershipLocationController.text.trim();
      if (dn.isEmpty || dp.isEmpty || dl.isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: const Text(
              'Please fill dealership name, phone, and location before sending the code.',
            ),
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
    }
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
      _loading = true;
    });
    try {
      final data = await ApiService.sendOtpLegacy(
        phone: '+964$phone',
        isDealer: _isDealer,
        dealershipName: _dealershipNameController.text.trim(),
        dealershipPhone: _dealershipPhoneController.text.trim(),
        dealershipLocation: _dealershipLocationController.text.trim(),
      );
      if (!mounted) return;
      final bool sent = data['sent'] == true;
      setState(() {
        _otpSent = true;
      });
      if (sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.verificationCodeSent),
          ),
        );
      } else if (data['dev_code'] != null && kDebugMode) {
        final String code = data['dev_code'].toString();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.devCodeTitle),
            content: Text(
              AppLocalizations.of(context)!.useCodeToVerify(code),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      } else {
        final String err =
            data['error']?.toString() ??
            AppLocalizations.of(context)!.couldNotSubmitListing;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: Text(err),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      String msg = e.message;
      if (e.statusCode == 429) {
        final retryAfter = e.body?['retry_after'];
        final seconds = retryAfter is int
            ? retryAfter
            : (retryAfter is num ? retryAfter.toInt() : null);
        if (seconds != null && seconds > 0) {
          final minutes = (seconds / 60).ceil();
          msg =
              '$msg Try again in $minutes minute${minutes == 1 ? '' : 's'}.';
        }
      }
      showDialog(
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
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _signup() async {
    if (!_acceptedTerms) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(acceptTermsRequiredText(context)),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    if (!_isDealer && username.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(
            '${AppLocalizations.of(context)!.usernameLabel} is required',
          ),
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
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_authType == 'email') {
        await authService.registerEmailWithVerification(
          username: _isDealer ? null : username,
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _isDealer
              ? _dealershipNameController.text.trim()
              : username,
          lastName: _isDealer ? '' : '',
          phoneNumber: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          isDealer: _isDealer,
          dealershipName: _dealershipNameController.text.trim(),
          dealershipPhone: _dealershipPhoneController.text.trim(),
          dealershipLocation: _dealershipLocationController.text.trim(),
        );
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Success'),
            content: const Text(
              'We sent a confirmation link to your email. '
              'Please verify your email to finish creating your account.',
            ),
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
      // Phone path: keep existing API calls for send_otp/signup, then persist tokens via ApiService
      final Map<String, dynamic> requestBody = <String, dynamic>{
        'password': _passwordController.text,
        'auth_type': _authType,
        if (!_isDealer) 'username': username,
        'phone': '+964${_phoneController.text.trim()}',
        'otp_code': _otpController.text.trim(),
        'is_dealer': _isDealer,
        if (_isDealer) ...<String, dynamic>{
          'dealership_name': _dealershipNameController.text.trim(),
          'dealership_phone': _dealershipPhoneController.text.trim(),
          'dealership_location': _dealershipLocationController.text.trim(),
        },
      };
      final data = await ApiService.signupLegacy(requestBody);
      final String? legacyToken = (data['token'] as String?)?.trim();
      final String? access = (data['access_token'] as String?)?.trim();
      final String? refresh = (data['refresh_token'] as String?)?.trim();
      final String? token = (legacyToken != null && legacyToken.isNotEmpty)
          ? legacyToken
          : access;
      if (token != null && token.isNotEmpty) {
        await ApiService.setAccessToken(token);
        if (refresh != null && refresh.isNotEmpty) {
          await ApiService.setRefreshToken(refresh);
        }
        final user = data['user'];
        await authService.activateSession(
          user: user is Map ? Map<String, dynamic>.from(user.cast<String, dynamic>()) : null,
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
      // No token: try login so we get tokens and profile
      try {
        final loginIdent = _authType == 'phone'
            ? '+964${_phoneController.text.trim()}'
            : username;
        await authService.login(loginIdent, _passwordController.text);
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      } catch (e, st) {
        logNonFatal(e, st);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.errorTitle),
            content: const Text(
              'Signup succeeded. Please log in to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.okAction),
              ),
            ],
          ),
        );
      }
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.okAction),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'SignupPage');
      String message =
          'Signup failed. Please check your details and try again.';
      if (e is ApiException) {
        if (e.statusCode == 409) {
          message =
              'An account with this email already exists. Try logging in or use Forgot password.';
        } else if (kDebugMode) {
          message = e.message;
        }
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.errorTitle),
          content: Text(message),
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
}
