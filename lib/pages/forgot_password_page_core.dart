part of 'forgot_password_page.dart';

mixin _ForgotPasswordPageCore on _ForgotPasswordPageActions {
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
                _codeSent
                    ? _checkYourPhoneTitle(context)
                    : _resetPasswordTitle(context),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _codeSent
                    ? _resetSmsSent(context, _phoneController.text)
                    : _forgotPasswordIntroPhone(context),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_codeSent) ...[
                const SizedBox(height: 16),
                Text(
                  _smsResetHint(context),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 32),
              if (!_codeSent) ...[
                TextFormField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isLoading) _sendReset();
                  },
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.phoneLabel,
                    hintText: AppLocalizations.of(
                      context,
                    )!.useInternationalFormat,
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
                  label: _sendSmsResetCode(context),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendReset,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(_sendSmsResetCode(context)),
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
