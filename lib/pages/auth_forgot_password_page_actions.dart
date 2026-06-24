part of 'auth_pages.dart';

mixin _ForgotPasswordPageActions on _ForgotPasswordPageFields {
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
    } catch (e) {
      developer.log(
        'Forgot password failed',
        name: 'ForgotPasswordPage',
        error: e,
      );
      if (mounted) {
        final message = e is ApiException && e.statusCode == 429
            ? _resetRateLimitedMessage(context)
            : (kDebugMode && e is ApiException
                  ? e.message
                  : (_recoveryMethod == 'phone'
                        ? _failedToSendSmsResetMessage(context)
                        : _failedToSendResetEmailMessage(context)));
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
}
