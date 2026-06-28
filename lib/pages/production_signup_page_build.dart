part of 'production_auth_pages.dart';

mixin _SignupPageBuild on _SignupPageActions {
  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightShell ? Colors.black87 : Colors.white;
    final mutedTextColor = isLightShell ? Colors.black54 : Colors.white70;
    final fillColor = isLightShell ? Colors.grey.shade100 : Colors.white10;
    final borderColor = isLightShell ? Colors.grey.shade400 : Colors.white54;

    InputDecoration authDecoration({
      required String labelText,
      String? hintText,
      Widget? prefixIcon,
      String? prefixText,
    }) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon,
        prefixText: prefixText,
        filled: true,
        fillColor: fillColor,
        labelStyle: TextStyle(color: mutedTextColor),
        hintStyle: TextStyle(color: mutedTextColor),
        prefixStyle: TextStyle(
          color: Color(0xFFFF6B00),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF6B00), width: 2),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.signupTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              // Authentication Type Selection
              Text(
                'Choose Authentication Method:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _authType,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _authType = value;
                    _otpSent = false;
                    _otpController.clear();
                  });
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          'Email',
                          style: TextStyle(color: textColor),
                        ),
                        value: 'email',
                        activeColor: Color(0xFFFF6B00),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          'Phone',
                          style: TextStyle(color: textColor),
                        ),
                        value: 'phone',
                        activeColor: Color(0xFFFF6B00),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Account type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I am registering as a dealership / dealer',
                  style: TextStyle(color: textColor),
                ),
                subtitle: Text(
                  _isDealer
                      ? 'Dealership details required; approval is pending until reviewed.'
                      : 'Leave off for a normal personal account.',
                  style: TextStyle(color: mutedTextColor, fontSize: 13),
                ),
                value: _isDealer,
                onChanged: (v) => setState(() => _isDealer = v),
              ),
              if (_isDealer) ...[
                SizedBox(height: 8),
                TextFormField(
                  controller: _dealershipNameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership name'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipPhoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(labelText: 'Dealership phone'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership phone is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipLocationController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(labelText: 'Dealership location'),
                  validator: (v) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (v == null || v.trim().isEmpty) {
                      return 'Dealership location is required';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 16),

              // Conditional fields based on auth type
              if (_authType == 'email') ...[
                TextFormField(
                  controller: _emailController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.emailAddress,
                  decoration: authDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email address',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(v.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
              ] else ...[
                TextFormField(
                  controller: _phoneController,
                  style: TextStyle(color: textColor),
                  keyboardType: TextInputType.phone,
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.enterPhoneNumber,
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
                      ? AppLocalizations.of(context)!.requiredField
                      : null,
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _otpController,
                        style: TextStyle(color: textColor),
                        decoration: authDecoration(
                          labelText: AppLocalizations.of(context)!.sendCode,
                        ),
                        validator: (v) => (!_otpSent)
                            ? AppLocalizations.of(context)!.sendCodeFirst
                            : ((v == null || v.trim().isEmpty)
                                  ? AppLocalizations.of(context)!.requiredField
                                  : null),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendOtp,
                      child: Text(_otpSent ? 'Resend' : 'Send code'),
                    ),
                  ],
                ),
              ],
              if (!_isDealer) ...[
                SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  style: TextStyle(color: textColor),
                  decoration: authDecoration(
                    labelText: AppLocalizations.of(context)!.usernameLabel,
                    hintText: 'Choose a username',
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) {
                      return '${AppLocalizations.of(context)!.usernameLabel} is required';
                    }
                    if (value.length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                style: TextStyle(color: textColor),
                obscureText: true,
                decoration: authDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return AppLocalizations.of(context)!.requiredField;
                  }
                  if (v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (!RegExp(r'[A-Z]').hasMatch(v)) {
                    return 'Password must contain at least one uppercase letter';
                  }
                  if (!RegExp(r'[a-z]').hasMatch(v)) {
                    return 'Password must contain at least one lowercase letter';
                  }
                  if (!RegExp(r'\d').hasMatch(v)) {
                    return 'Password must contain at least one number';
                  }
                  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) {
                    return 'Password must contain at least one special character';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              CheckboxListTile(
                value: _acceptedTerms,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _acceptedTerms = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      trLegacyText(
                        context,
                        'I agree to the ',
                        ar: 'أوافق على ',
                        ku: 'ڕازیم بە ',
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.terms,
                          ),
                        ),
                      ),
                      child: Text(
                        trLegacyText(
                          context,
                          'Terms',
                          ar: 'الشروط',
                          ku: 'مەرجەکان',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      trLegacyText(context, ' and ', ar: ' و', ku: ' و'),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        AppPageRoute(
                          builder: (_) => const LegalDocumentPage(
                            document: LegalDocument.privacy,
                          ),
                        ),
                      ),
                      child: Text(
                        trLegacyText(
                          context,
                          'Privacy Policy',
                          ar: 'سياسة الخصوصية',
                          ku: 'تایبەتمەندی',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.createAccount,
                child: ElevatedButton(
                  onPressed: (_loading || !_acceptedTerms) ? null : _signup,
                  child: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppLocalizations.of(context)!.createAccount),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: Text(AppLocalizations.of(context)!.haveAccountLogin),
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
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                navigateMainShellTab(context, '/profile');
              }
              break;
          }
        },
      ),
    );
  }
}
