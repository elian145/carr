part of 'production_auth_pages.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e, st) {
      if (!mounted) return;
      logNonFatal(e, st, 'LoginPage');
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
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.loginTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.emailOrPhoneLabel,
                  hintText: AppLocalizations.of(context)!.enterEmailOrPhoneHint,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppLocalizations.of(context)!.emailOrPhoneRequired
                    : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.passwordLabel,
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? AppLocalizations.of(context)!.requiredField
                    : null,
              ),
              SizedBox(height: 20),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.navLogin,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppLocalizations.of(context)!.navLogin),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/forgot-password'),
                child: Text(AppLocalizations.of(context)!.forgotPasswordLink),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(AppLocalizations.of(context)!.createAccount),
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
              // Already on login
              break;
          }
        },
      ),
    );
  }
}
