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

  String _cardDesignLabel(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'ar':
        return 'تصميم البطاقة';
      case 'ku':
        return 'دیزاینی کارت';
      default:
        return 'Card design';
    }
  }

  String _designLabel(BuildContext context, int design) {
    final number = design.toString().padLeft(2, '0');
    switch (Localizations.localeOf(context).languageCode) {
      case 'ar':
        return 'التصميم $number';
      case 'ku':
        return 'دیزاین $number';
      default:
        return 'Design $number';
    }
  }

  Future<void> _showCardDesignPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .82,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _cardDesignLabel(sheetContext),
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Horizontal'),
                  Tab(text: 'Grid'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _CardDesignPreviewGrid(
                      notifier: ListingLayoutPrefs.horizontalCardDesign,
                      horizontal: true,
                      labelBuilder: (value) =>
                          _designLabel(sheetContext, value),
                      onSelected: ListingLayoutPrefs.setHorizontalCardDesign,
                    ),
                    _CardDesignPreviewGrid(
                      notifier: ListingLayoutPrefs.gridCardDesign,
                      horizontal: false,
                      labelBuilder: (value) =>
                          _designLabel(sheetContext, value),
                      onSelected: ListingLayoutPrefs.setGridCardDesign,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFFF6B00), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.orbitron(
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
          ValueListenableBuilder<int>(
            valueListenable: ListingLayoutPrefs.horizontalCardDesign,
            builder: (context, horizontalDesign, _) {
              return ValueListenableBuilder<int>(
                valueListenable: ListingLayoutPrefs.gridCardDesign,
                builder: (context, gridDesign, _) => rowTile(
                  icon: Icons.view_carousel_outlined,
                  title: _cardDesignLabel(context),
                  subtitle:
                      'Horizontal ${horizontalDesign.toString().padLeft(2, '0')} · Grid ${gridDesign.toString().padLeft(2, '0')}',
                  trailing: Icon(
                    Icons.chevron_right,
                    color: isLightShell ? Colors.grey.shade700 : Colors.white70,
                  ),
                  onTap: _showCardDesignPicker,
                ),
              );
            },
          ),
          Divider(height: 1, color: dividerColor),
          rowTile(
            icon: Icons.notifications_active_outlined,
            title: loc.settingsEnablePush,
            trailing: Switch.adaptive(
              value: _pushEnabled,
              activeThumbColor: const Color(0xFFFF6B00),
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
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLightShell
          ? Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: bodyChild,
            )
          : Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 110),
                child: bodyChild,
              ),
            ),
    );
  }
}

class _CardDesignPreviewGrid extends StatelessWidget {
  const _CardDesignPreviewGrid({
    required this.notifier,
    required this.horizontal,
    required this.labelBuilder,
    required this.onSelected,
  });

  final ValueNotifier<int> notifier;
  final bool horizontal;
  final String Function(int) labelBuilder;
  final Future<void> Function(int) onSelected;

  static const _accents = [
    Color(0xFFFF5A00),
    Color(0xFF1677FF),
    Color(0xFF00897B),
    Color(0xFF7E57C2),
    Color(0xFFE53935),
    Color(0xFF3949AB),
    Color(0xFF2E7D32),
    Color(0xFFF9A825),
    Color(0xFFD81B60),
    Color(0xFF00838F),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 4
            : constraints.maxWidth >= 430
            ? 3
            : 2;
        return ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (context, selected, _) => GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: horizontal ? 1.35 : .92,
            ),
            itemCount: 20,
            itemBuilder: (context, index) {
              final design = index + 1;
              final accent = _accents[index % _accents.length];
              final active = design == selected;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(design),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: .12)
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active
                          ? accent
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: _AbstractCardPreview(
                          design: design,
                          horizontal: horizontal,
                          accent: accent,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (active) ...[
                            Icon(Icons.check_circle, size: 14, color: accent),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              labelBuilder(design),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _AbstractCardPreview extends StatelessWidget {
  const _AbstractCardPreview({
    required this.design,
    required this.horizontal,
    required this.accent,
  });

  final int design;
  final bool horizontal;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final composition = design % 5;
    final image = Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(design.isEven ? 4 : 10),
      ),
      child: Icon(Icons.directions_car, color: accent, size: 25),
    );
    final lines = Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: composition == 4
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(
          widthFactor: .85,
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        if (composition != 1)
          FractionallySizedBox(
            widthFactor: .58,
            child: Container(
              height: composition == 3 ? 2 : 6,
              color: composition == 3
                  ? accent
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 25,
              height: 10,
              decoration: BoxDecoration(
                color: composition.isEven
                    ? accent.withValues(alpha: .18)
                    : Colors.transparent,
                border: composition.isOdd ? Border.all(color: accent) : null,
                borderRadius: BorderRadius.circular(composition == 2 ? 8 : 3),
              ),
            ),
            Container(
              width: 34,
              height: 12,
              decoration: BoxDecoration(
                color: design % 4 == 0 ? Colors.transparent : accent,
                border: design % 4 == 0 ? Border.all(color: accent) : null,
                borderRadius: BorderRadius.circular(design % 3 == 0 ? 10 : 3),
              ),
            ),
          ],
        ),
      ],
    );
    return horizontal
        ? Row(
            textDirection: design % 3 == 0
                ? TextDirection.rtl
                : TextDirection.ltr,
            children: [
              Expanded(flex: 4 + design % 3, child: image),
              const SizedBox(width: 6),
              Expanded(flex: 6, child: lines),
            ],
          )
        : Column(
            children: [
              Expanded(flex: 4 + design % 3, child: image),
              const SizedBox(height: 5),
              Expanded(flex: 5, child: lines),
            ],
          );
  }
}
