part of 'production_account_pages.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pushEnabled = true;
  final GlobalKey<PopupMenuButtonState<String?>> _languageMenuKey =
      GlobalKey<PopupMenuButtonState<String?>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setLocale(String? code) async {
    if (code == null) {
      await LocaleController.setLocale(null);
    } else {
      await LocaleController.setLocale(Locale(code));
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = sp.getBool('push_enabled') ?? true;
    setState(() {
      _pushEnabled = enabled;
    });
  }

  Future<void> _togglePush(bool v) async {
    await PushNotificationService.setPushEnabled(v);
    if (!mounted) return;
    setState(() {
      _pushEnabled = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = context.watch<ThemeProvider>();
    final currentLocale = LocaleController.currentLocale.value?.languageCode;
    final isLightShell = Theme.of(context).brightness == Brightness.light;

    final tileFill = isLightShell
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );
    final tileBorder = isLightShell ? Colors.grey.shade200 : Colors.white12;
    final titleColor = isLightShell ? Colors.grey.shade900 : Colors.white;
    final subtitleColor = isLightShell ? Colors.grey.shade600 : Colors.white70;
    final dividerColor = isLightShell ? Colors.grey.shade200 : Colors.white12;

    String localeLabel(String? code) {
      if (code == null) return loc.settingsSystem;
      switch (code) {
        case 'en':
          return 'English';
        case 'ar':
          return 'العربية';
        case 'ku':
          return 'کوردی';
        default:
          return code;
      }
    }

    Widget rowTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.brandOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppFonts.orbitron(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      );
    }

    Widget settingsCard(List<Widget> children) {
      return Container(
        decoration: BoxDecoration(
          color: tileFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tileBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLightShell ? 0.05 : 0.20),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(children: children),
        ),
      );
    }

    final bodyChild = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        settingsCard([
          rowTile(
            icon: Icons.edit_outlined,
            title: loc.editProfileAction,
            trailing: Icon(
              Icons.chevron_right,
              color: isLightShell ? Colors.grey.shade700 : Colors.white70,
            ),
            onTap: () async {
              if (ApiService.accessToken == null ||
                  ApiService.accessToken!.isEmpty) {
                Navigator.pushNamed(context, '/login');
                return;
              }
              await Navigator.pushNamed(context, '/edit-profile');
            },
          ),
          Divider(height: 1, color: dividerColor),
          rowTile(
            icon: Icons.language,
            title: loc.settingsLanguageTitle,
            subtitle: localeLabel(currentLocale),
            trailing: PopupMenuButton<String?>(
              key: _languageMenuKey,
              tooltip: '',
              position: PopupMenuPosition.under,
              onSelected: (v) => _setLocale(v),
              itemBuilder: (context) => [
                PopupMenuItem<String?>(
                  value: null,
                  child: Text(loc.settingsSystem),
                ),
                const PopupMenuItem<String?>(
                  value: 'en',
                  child: Text('English'),
                ),
                const PopupMenuItem<String?>(
                  value: 'ar',
                  child: Text('العربية'),
                ),
                const PopupMenuItem<String?>(value: 'ku', child: Text('کوردی')),
              ],
              icon: Icon(
                Icons.expand_more,
                color: isLightShell ? Colors.grey.shade700 : Colors.white70,
              ),
            ),
            onTap: () => _languageMenuKey.currentState?.showButtonMenu(),
          ),
          Divider(height: 1, color: dividerColor),
          rowTile(
            icon: theme.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            title: loc.settingsThemeTitle,
            subtitle: theme.themeMode == ThemeMode.system
                ? loc.settingsSystem
                : theme.themeMode == ThemeMode.dark
                ? loc.settingsDark
                : loc.settingsLight,
            trailing: Icon(
              theme.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: isLightShell ? Colors.grey.shade700 : Colors.white70,
            ),
            onTap: theme.toggleTheme,
          ),
          Divider(height: 1, color: dividerColor),
          rowTile(
            icon: Icons.notifications_active_outlined,
            title: loc.settingsEnablePush,
            trailing: Switch.adaptive(
              value: _pushEnabled,
              activeThumbColor: AppColors.brandOrange,
              onChanged: _togglePush,
            ),
            onTap: () => _togglePush(!_pushEnabled),
          ),
        ]),
      ],
    );

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      appBar: AppBar(
        title: Text(loc.settingsTitle),
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLightShell
          ? Padding(
              padding: EdgeInsets.only(
                bottom: 110,
                left: AppResponsive.pagePadding(context).left,
                right: AppResponsive.pagePadding(context).right,
              ),
              child: AppResponsive.constrainContent(
                bodyChild,
                maxWidth: AppResponsive.settingsContentMaxWidth,
              ),
            )
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: 110,
                  left: AppResponsive.pagePadding(context).left,
                  right: AppResponsive.pagePadding(context).right,
                ),
                child: AppResponsive.constrainContent(
                  bodyChild,
                  maxWidth: AppResponsive.settingsContentMaxWidth,
                ),
              ),
            ),
    );
  }
}
