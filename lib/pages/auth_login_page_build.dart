part of 'auth_pages.dart';

mixin _LoginPageBuild on _LoginPageActions {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.loginTitle),
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
                Icons.directions_car,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                _welcomeBackText(context),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: _usernameOrEmailLabel(context),
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _pleaseEnterUsernameOrEmail(context);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
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
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) {
                  if (!_isLoading) _login();
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _pleaseEnterPassword(context);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.loginAction,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(AppLocalizations.of(context)!.loginAction),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/forgot-password');
                },
                child: Text(_forgotPasswordQuestion(context)),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_dontHaveAccount(context), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/register');
                    },
                    child: Text(AppLocalizations.of(context)!.createAccount),
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
