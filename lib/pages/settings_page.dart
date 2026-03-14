import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _pushKey = 'push_enabled';
  static const String _apiOverrideKey = 'api_base_override';

  bool _pushEnabled = true;
  bool _loading = true;
  String? _apiOverride;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final enabled = sp.getBool(_pushKey);
      final apiOverride = sp.getString(_apiOverrideKey);
      if (!mounted) return;
      setState(() {
        _pushEnabled = enabled ?? true;
        _apiOverride = apiOverride?.trim().isEmpty == true ? null : apiOverride?.trim();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushEnabled = true;
        _apiOverride = null;
        _loading = false;
      });
    }
  }

  Future<void> _setPushEnabled(bool v) async {
    setState(() => _pushEnabled = v);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_pushKey, v);
    } catch (_) {}
  }

  Future<void> _setLocale(String? code) async {
    if (code == null) {
      await LocaleController.setLocale(null);
    } else {
      await LocaleController.setLocale(Locale(code));
    }
  }

  Future<void> _deleteAccountTapped() async {
    final loc = AppLocalizations.of(context)!;
    final passwordResult = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final passwordController = TextEditingController();
        final locDialog = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(locDialog.deleteAccountTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locDialog.deleteAccountBody),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: locDialog.passwordOptionalConfirm,
                    hintText: locDialog.confirmWithPasswordHint,
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
              child: Text(locDialog.cancelAction),
            ),
            TextButton(
              onPressed: () {
                final p = passwordController.text.trim();
                Navigator.pop(ctx, p); // empty string = no password, non-empty = password
              },
              child: Text(
                locDialog.deleteMyAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        );
      },
    );
    if (passwordResult == null || !mounted) return;

    final auth = AuthService();
    try {
      await auth.deleteAccount(password: passwordResult.isEmpty ? null : passwordResult);
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

  Future<void> _editApiBase() async {
    if (!allowRuntimeApiBaseOverride()) return;
    final controller = TextEditingController(
      text: _apiOverride ?? effectiveApiBase(),
    );
    final loc = AppLocalizations.of(context)!;

    final String? next = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(loc.apiBaseTitle),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: loc.apiBaseHint,
            ),
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelAction),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(loc.resetButton),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(loc.save),
            ),
          ],
        );
      },
    );

    if (next == null) return;
    final v = next.trim();

    try {
      final sp = await SharedPreferences.getInstance();
      if (v.isEmpty) {
        await sp.remove(_apiOverrideKey);
        setRuntimeApiBaseOverride(null);
      } else {
        // Basic normalization (don’t enforce scheme here; config.dart will validate for release).
        await sp.setString(_apiOverrideKey, v);
        setRuntimeApiBaseOverride(v);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _apiOverride = v.isEmpty ? null : v;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.apiBaseUpdatedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthService>();

    final currentLocale = LocaleController.currentLocale.value?.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.settingsTitle ?? 'Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 8),
                ListTile(
                  title: Text(loc?.settingsThemeTitle ?? 'Theme'),
                  subtitle: Text(
                    theme.themeMode == ThemeMode.system
                        ? (loc?.settingsSystem ?? 'System')
                        : theme.themeMode == ThemeMode.dark
                            ? (loc?.settingsDark ?? 'Dark')
                            : (loc?.settingsLight ?? 'Light'),
                  ),
                  trailing: DropdownButton<ThemeMode>(
                    value: theme.themeMode,
                    onChanged: (m) {
                      if (m == null) return;
                      theme.setThemeMode(m);
                    },
                    items: [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text(loc?.settingsSystem ?? 'System'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text(loc?.settingsLight ?? 'Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text(loc?.settingsDark ?? 'Dark'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(loc?.settingsLanguageTitle ?? 'Language'),
                  subtitle: Text(
                    currentLocale == null
                        ? (loc?.settingsSystem ?? 'System')
                        : currentLocale == 'en'
                            ? (loc?.english ?? 'English')
                            : currentLocale == 'ar'
                                ? (loc?.arabic ?? 'Arabic')
                                : currentLocale == 'ku'
                                    ? (loc?.kurdish ?? 'Kurdish')
                                    : currentLocale,
                  ),
                  trailing: DropdownButton<String?>(
                    value: currentLocale,
                    onChanged: (v) => _setLocale(v),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(loc?.settingsSystem ?? 'System'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'en',
                        child: Text(loc?.english ?? 'English'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'ar',
                        child: Text(loc?.arabic ?? 'Arabic'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'ku',
                        child: Text(loc?.kurdish ?? 'Kurdish'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(loc?.settingsEnablePush ?? 'Push notifications'),
                  subtitle: Text(
                    _pushEnabled
                        ? (loc?.enabledLabel ?? 'Enabled')
                        : (loc?.disabledLabel ?? 'Disabled'),
                  ),
                  value: _pushEnabled,
                  onChanged: (v) => _setPushEnabled(v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(loc?.apiLabel ?? 'API'),
                  subtitle: Text(
                    _apiOverride == null
                        ? effectiveApiBase()
                        : '${effectiveApiBase()}\n(override: $_apiOverride)',
                  ),
                  isThreeLine: _apiOverride != null,
                  trailing: allowRuntimeApiBaseOverride()
                      ? const Icon(Icons.edit_outlined)
                      : null,
                  onTap: allowRuntimeApiBaseOverride() ? _editApiBase : null,
                ),
                const Divider(height: 1),
                if (auth.isAuthenticated) ...[
                  ListTile(
                    title: Text(loc?.accountLabel ?? 'Account'),
                    subtitle: Text(auth.userName.isEmpty ? (loc?.loggedIn ?? 'Logged in') : auth.userName),
                  ),
                  ListTile(
                    title: Text(loc?.changePasswordTitle ?? 'Change password'),
                    leading: const Icon(Icons.lock_outline),
                    onTap: () => Navigator.pushNamed(context, '/change-password'),
                  ),
                  ListTile(
                    title: Text(
                      loc?.deleteAccountTitle ?? 'Delete account',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                    onTap: _deleteAccountTapped,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await AuthService().logout();
                        if (!context.mounted) return;
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(loc?.logout ?? 'Logout'),
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      icon: const Icon(Icons.login),
                      label: Text(loc?.loginAction ?? 'Login'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

