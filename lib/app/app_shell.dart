import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/deep_link_service.dart';
import '../shared/i18n/ku_delegates.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';
import '../widgets/edge_swipe_back.dart';
import 'navigator_key.dart';
import 'providers.dart';

/// Initializes deep links after the first frame.
class AppWithDeepLinks extends StatefulWidget {
  const AppWithDeepLinks({super.key, required this.child});

  final Widget child;

  @override
  State<AppWithDeepLinks> createState() => _AppWithDeepLinksState();
}

class _AppWithDeepLinksState extends State<AppWithDeepLinks> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init(appNavigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared MaterialApp shell for production and refactor entrypoints.
class CarNetAppShell extends StatelessWidget {
  const CarNetAppShell({
    super.key,
    required this.routes,
  });

  final Map<String, WidgetBuilder> routes;

  static const List<LocalizationsDelegate<dynamic>> localizationDelegates = [
    ...AppLocalizations.localizationsDelegates,
    KuMaterialLocalizationsDelegate(),
    KuWidgetsLocalizationsDelegate(),
    KuCupertinoLocalizationsDelegate(),
  ];

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('ku'),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildAppProviders(),
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) => Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) => AppWithDeepLinks(
            child: MaterialApp(
              navigatorKey: appNavigatorKey,
              title: 'CarNet',
              debugShowCheckedModeBanner: false,
              builder: (context, child) => EdgeSwipeBack(
                navigatorKey: appNavigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
              theme: AppThemes.lightTheme,
              darkTheme: AppThemes.darkTheme,
              themeMode: themeProvider.themeMode,
              locale: locale,
              supportedLocales: supportedLocales,
              localizationsDelegates: localizationDelegates,
              localeResolutionCallback: (deviceLocale, supported) {
                if (locale != null) return locale;
                if (deviceLocale == null) return const Locale('en');
                for (final candidate in supported) {
                  if (candidate.languageCode == deviceLocale.languageCode) {
                    return candidate;
                  }
                }
                return const Locale('en');
              },
              initialRoute: '/',
              routes: routes,
            ),
          ),
        ),
      ),
    );
  }
}
