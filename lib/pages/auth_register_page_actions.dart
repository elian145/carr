part of 'auth_pages.dart';

mixin _RegisterPageActions on _RegisterPageFields {

  bool _hasPassword() => _passwordController.text.trim().isNotEmpty;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.pleaseFixHighlightedFields ?? 'Please fix the highlighted fields',
          ),
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
          username: _isDealer ? null : _usernameController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _hasPassword() ? _passwordController.text : null,
          isDealer: _isDealer,
          dealershipName: _dealershipNameController.text.trim(),
          dealershipPhone: _dealershipPhoneController.text.trim(),
          dealershipLocation: _dealershipLocationController.text.trim(),
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
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      } else {
        await authService.registerEmailWithVerification(
          username: _isDealer ? null : _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          phoneNumber: _phoneController.text.isNotEmpty
              ? _phoneController.text
              : null,
          isDealer: _isDealer,
          dealershipName: _dealershipNameController.text.trim(),
          dealershipPhone: _dealershipPhoneController.text.trim(),
          dealershipLocation: _dealershipLocationController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We sent a confirmation link to your email. Please verify your email to finish creating your account.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      developer.log('Registration failed', name: 'RegisterPage', error: e);
      if (mounted) {
        String message = _registrationFailedMessage(context);
        if (e is ApiException) {
          if (e.statusCode == 409) {
            message =
                'An account with this email already exists. Try logging in or use Forgot password.';
          } else if (kDebugMode) {
            message = e.message;
          }
        }
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
        username: _isDealer ? null : _usernameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _hasPassword() ? _passwordController.text : null,
        isDealer: _isDealer,
        dealershipName: _dealershipNameController.text.trim(),
        dealershipPhone: _dealershipPhoneController.text.trim(),
        dealershipLocation: _dealershipLocationController.text.trim(),
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
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)!.otpFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }
}
