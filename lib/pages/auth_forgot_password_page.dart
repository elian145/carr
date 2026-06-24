part of 'auth_pages.dart';

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

  /// `'email'` or `'phone'` — controls which identifier is sent to `/auth/forgot-password`.
  String _recoveryMethod = 'email';

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
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
                      hintText: AppLocalizations.of(context)!.useInternationalFormat,
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
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendReset,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(
                          _recoveryMethod == 'phone'
                              ? _sendSmsResetCode(context)
                              : _sendResetLink(context),
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
