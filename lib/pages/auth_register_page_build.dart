part of 'auth_pages.dart';

mixin _RegisterPageBuild on _RegisterPageActions {
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
              RadioGroup<String>(
                groupValue: _authType,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _authType = v;
                    _otpSent = false;
                    _otpController.clear();
                  });
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
              Text(
                'Account type',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I am registering as a dealership / dealer'),
                subtitle: Text(
                  _isDealer
                      ? 'You will submit dealership details; approval is pending until reviewed.'
                      : 'Leave off for a normal personal account.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _isDealer,
                onChanged: (v) => setState(() => _isDealer = v),
              ),
              if (_isDealer) ...[
                const SizedBox(height: 4),
                TextFormField(
                  controller: _dealershipNameController,
                  decoration: const InputDecoration(
                    labelText: 'Dealership name',
                    prefixIcon: Icon(Icons.storefront_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Dealership name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Dealership phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Dealership phone is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dealershipLocationController,
                  decoration: const InputDecoration(
                    labelText: 'Dealership location',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (!_isDealer) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Dealership location is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
              ],
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
              if (!_isDealer) ...[
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
              ],
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
                      _isSendingOtp
                          ? '...'
                          : AppLocalizations.of(context)!.sendOtp,
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
                    if (_authType != 'phone') {
                      return null;
                    }
                    if (!_otpSent) {
                      return AppLocalizations.of(context)!.sendCodeFirst;
                    }
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
              const SizedBox(height: 8),
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
                  if (_authType == 'phone' &&
                      (value == null || value.isEmpty)) {
                    return null;
                  }
                  if (value == null || value.isEmpty) {
                    return _pleaseEnterPassword(context);
                  }
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
                  if (_authType == 'phone' && pw.trim().isEmpty) {
                    return null;
                  }
                  if (value == null || value.isEmpty) {
                    return _pleaseConfirmPassword(context);
                  }
                  if (value != pw) {
                    return _passwordsDoNotMatch(context);
                  }
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
