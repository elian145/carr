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

  bool _pushEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final enabled = sp.getBool(_pushKey);
      if (!mounted) return;
      setState(() {
        _pushEnabled = enabled ?? true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pushEnabled = true;
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
                  subtitle: Text(effectiveApiBase()),
                ),
                const Divider(height: 1),
                if (auth.isAuthenticated) ...[
                  ListTile(
                    title: Text(loc?.accountLabel ?? 'Account'),
                    subtitle: Text(auth.userName.isEmpty ? (loc?.loggedIn ?? 'Logged in') : auth.userName),
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

