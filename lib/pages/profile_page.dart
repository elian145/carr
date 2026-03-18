import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/media/media_url.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = false;
  String? _error;

  Future<void> _showAuthRequiredDialog(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc?.loginTitle ?? 'Login'),
          content: Text(
            loc?.notLoggedIn ?? 'You need to sign up or log in to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc?.cancelAction ?? 'Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/signup');
              },
              child: Text(loc?.signupTitle ?? 'Sign Up'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/login');
              },
              child: Text(loc?.loginAction ?? 'Log In'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendEmailVerification(BuildContext context, AuthService auth) async {
    try {
      await auth.sendEmailVerification();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.verificationEmailSent),
          backgroundColor: Colors.green,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showPhoneVerifyDialog(BuildContext context, String phone, AuthService auth) async {
    final codeController = TextEditingController();
    bool codeSent = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            final locDialog = AppLocalizations.of(ctx)!;
            return AlertDialog(
              title: Text(locDialog.verifyPhoneDialogTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(locDialog.verifyPhoneDialogMessage(phone)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: locDialog.sixDigitCodeLabel,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(locDialog.cancelAction),
                ),
                if (!codeSent)
                  FilledButton(
                    onPressed: () async {
                      try {
                        await ApiService.sendPhoneVerificationCode(phone);
                        if (!ctx2.mounted) return;
                        setDialogState(() => codeSent = true);
                        ScaffoldMessenger.of(ctx2).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(ctx2)!.codeSentEnterAbove)),
                        );
                      } catch (e) {
                        if (!ctx2.mounted) return;
                        ScaffoldMessenger.of(ctx2).showSnackBar(
                          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                        );
                      }
                    },
                    child: Text(locDialog.sendCodeButton),
                  ),
                FilledButton(
                  onPressed: () async {
                    final code = codeController.text.trim();
                    if (code.length != 6) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(ctx2)!.pleaseEnter6DigitCode), backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    try {
                      await ApiService.verifyPhone(phone, code);
                      if (!ctx2.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(ctx2)!.phoneVerifiedSuccess), backgroundColor: Colors.green),
                      );
                      _refresh();
                    } catch (e) {
                      if (!ctx2.mounted) return;
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
                      );
                    }
                  },
                  child: Text(locDialog.verifyButton),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted) await _refresh();
  }

  Future<void> _deleteAccountTapped() async {
    final loc = AppLocalizations.of(context)!;
    final passwordResult = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final passwordController = TextEditingController();
        final locD = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(locD.deleteAccountTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locD.deleteAccountBody),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: locD.passwordOptionalConfirm,
                    hintText: locD.confirmWithPasswordHint,
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locD.cancelAction),
            ),
            TextButton(
              onPressed: () {
                final p = passwordController.text.trim();
                Navigator.pop(ctx, p);
              },
              child: Text(
                locD.deleteMyAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        );
      },
    );
    if (passwordResult == null || !mounted) return;
    try {
      await AuthService().deleteAccount(password: passwordResult.isEmpty ? null : passwordResult);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.accountDeletedSnackbar)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _refresh() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Refresh the profile info from server.
      await ApiService.getProfile();
      // Keep AuthService consistent by calling initialize (loads profile + sockets).
      // This is best-effort and safe even if already initialized.
      await auth.initialize();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

    final user = auth.currentUser;
    final username = (user?['username'] ?? '').toString();
    final email = (user?['email'] ?? '').toString();
    final phone = (user?['phone_number'] ?? user?['phone'] ?? '').toString();
    final realEmail = email.isNotEmpty && !email.endsWith('@phone.local');
    final primaryContact = realEmail ? email : (phone.isNotEmpty ? phone : email);
    final isVerified = user?['is_verified'] == true;
    final firstName = (user?['first_name'] ?? '').toString();
    final lastName = (user?['last_name'] ?? '').toString();
    final fullName = ('$firstName $lastName').trim();
    final pic = (user?['profile_picture'] ?? '').toString();
    final picUrl = buildMediaUrl(pic);
    final isAuthenticated = auth.isAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.profileTitle ?? 'Profile'),
        actions: [
          IconButton(
            tooltip: loc?.settingsTitle ?? 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Text(_error!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!isAuthenticated) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.black12,
                              child: Icon(
                                Icons.person_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Guest',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Sign in to access your profile features.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/login'),
                              child: Text(loc?.loginAction ?? 'Log In'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isAuthenticated) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.black12,
                              backgroundImage: picUrl.isNotEmpty
                                  ? NetworkImage(picUrl)
                                  : null,
                              child: picUrl.isEmpty
                                  ? const Icon(Icons.person, size: 32)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName.isEmpty ? username : fullName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (username.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('@$username'),
                                  ],
                                  if (primaryContact.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(primaryContact),
                                  ],
                                  if (realEmail && phone.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(phone),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(loc?.editProfileAction ?? 'Edit profile'),
                          onTap: () async {
                            if (!isAuthenticated) {
                              await _showAuthRequiredDialog(context);
                              return;
                            }
                            final result = await Navigator.pushNamed(
                              context,
                              '/edit-profile',
                            );
                            if (!mounted) return;
                            if (result == true) {
                              await _refresh();
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.favorite_border),
                          title: Text(loc?.favoritesTitle ?? 'Favorites'),
                          onTap: () async {
                            if (!isAuthenticated) {
                              await _showAuthRequiredDialog(context);
                              return;
                            }
                            Navigator.pushNamed(context, '/favorites');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.list_alt_outlined),
                          title: Text(loc?.myListingsTitle ?? 'My listings'),
                          onTap: () async {
                            if (!isAuthenticated) {
                              await _showAuthRequiredDialog(context);
                              return;
                            }
                            Navigator.pushNamed(context, '/my_listings');
                          },
                        ),
                        if (!isVerified && (realEmail || phone.isNotEmpty)) ...[
                          const Divider(height: 1),
                          if (email.isNotEmpty && !email.endsWith('@phone.local'))
                            ListTile(
                              leading: const Icon(Icons.mark_email_unread_outlined),
                              title: Text(loc?.verifyEmailAction ?? 'Verify email'),
                              subtitle: Text(loc?.sendVerificationLinkToEmail ?? 'Send a verification link to your email'),
                              onTap: () => _sendEmailVerification(context, auth),
                            ),
                          if (phone.isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.phone_android_outlined),
                              title: Text(loc?.verifyPhoneAction ?? 'Verify phone'),
                              subtitle: Text(loc?.receiveCodeBySms ?? 'Receive a code by SMS'),
                              onTap: () => _showPhoneVerifyDialog(context, phone, auth),
                            ),
                        ],
                        if (isAuthenticated) ...[
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              Icons.delete_forever_outlined,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              loc?.deleteAccountTitle ?? 'Delete account',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () async {
                              await _deleteAccountTapped();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            if (!isAuthenticated) {
                              await _showAuthRequiredDialog(context);
                              return;
                            }
                            await AuthService().logout();
                            if (!context.mounted) return;
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                    icon: const Icon(Icons.logout),
                    label: Text(loc?.logout ?? 'Logout'),
                  ),
                ],
              ),
            ),
    );
  }
}

