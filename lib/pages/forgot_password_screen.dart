import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) {
    final v = value.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);
  }

  String _friendlyFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is invalid.';
      case 'missing-email':
        return 'Please enter your email address.';
      case 'user-not-found':
        // Avoid account enumeration; keep generic.
        return 'If an account exists for that email, a reset link will be sent.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'Password reset is not enabled for this project.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Something went wrong. Please try again.';
    }
  }

  Future<void> _send() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _loading = true);
    try {
      // Ensure Firebase is initialized (bootstrap does this post-frame, but this makes the screen robust).
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final email = _emailController.text.trim();
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Please check your inbox.'),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final msg = (e.message ?? '').contains('Failed to load FirebaseOptions')
          ? 'Firebase is not configured for this app build.\n\n'
              'Fix: Download `google-services.json` from Firebase Console and place it under:\n'
              '- `android/app/src/dev/google-services.json` (for dev flavor)\n'
              '- `android/app/src/stage/google-services.json` (for stage flavor)\n'
              '- `android/app/src/prod/google-services.json` (for prod flavor)\n\n'
              'Then run `flutter clean` and rebuild.'
          : (e.message?.trim().isNotEmpty == true ? e.message!.trim() : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyFirebaseError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot password'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.12),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 0,
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: theme.dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 6),
                          Icon(
                            Icons.lock_reset_rounded,
                            size: 44,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Reset your password',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Enter the email address on your account and we'll send you a reset link.",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _emailController,
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'name@example.com',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Email is required';
                              if (!_isValidEmail(s)) return 'Enter a valid email address';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _loading ? null : _send,
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Send reset link'),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _loading ? null : () => Navigator.pop(context),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

