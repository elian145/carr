import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context)!;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthService>();
      await auth.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.passwordUpdated)),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.changePasswordTitle),
      ),
      body: !auth.isAuthenticated
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(loc.loginRequired),
              ),
            )
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _currentController,
                      obscureText: !_showCurrent,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: loc.currentPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showCurrent = !_showCurrent),
                          icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return loc.requiredField;
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _newController,
                      obscureText: !_showNew,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: loc.newPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showNew = !_showNew),
                          icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return loc.requiredField;
                        if (s.length < 8) return loc.passwordMin8;
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: !_showConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: loc.confirmPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _showConfirm = !_showConfirm),
                          icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return loc.requiredField;
                        if (s != _newController.text.trim()) return loc.passwordsDoNotMatch;
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(loc.updatePasswordAction),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

