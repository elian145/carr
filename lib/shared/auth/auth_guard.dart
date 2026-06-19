import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../shell/main_shell_navigation.dart';

/// Redirects to `/login` when the user is not authenticated; otherwise shows [child].
///
/// [allowGuest] — favorites/profile show their own login prompts when logged out.
/// [sellFlow] — sell shows a login/signup dialog instead of an immediate redirect.
class AuthGuard extends StatelessWidget {
  const AuthGuard({
    super.key,
    required this.child,
    this.allowGuest = false,
    this.sellFlow = false,
  });

  final Widget child;
  final bool allowGuest;
  final bool sellFlow;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    if (auth.isAuthenticated || allowGuest) {
      return child;
    }
    if (auth.isLoading || ApiService.isAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (sellFlow) {
      return const SellAuthPrompt();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Shown when a logged-out user opens Sell; offers login / signup or cancel.
class SellAuthPrompt extends StatefulWidget {
  const SellAuthPrompt({super.key});

  @override
  State<SellAuthPrompt> createState() => _SellAuthPromptState();
}

class _SellAuthPromptState extends State<SellAuthPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAuthDialog());
  }

  Future<void> _showAuthDialog() async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    var handled = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(loc.sellRequiresAuthTitle),
        content: Text(loc.sellRequiresAuthBody),
        actions: [
          TextButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              navigateMainShellTab(context, '/');
            },
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, '/signup');
            },
            child: Text(loc.signupTitle),
          ),
          FilledButton(
            onPressed: () {
              handled = true;
              Navigator.pop(ctx);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: Text(loc.loginAction),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (!handled) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
