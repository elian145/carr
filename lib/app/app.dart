import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../l10n/app_localizations.dart';
import '../services/deep_link_service.dart';
import '../shared/i18n/ku_delegates.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';
import '../widgets/edge_swipe_back.dart';
import 'providers.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class _AppWithDeepLinks extends StatefulWidget {
  const _AppWithDeepLinks({required this.child});

  final Widget child;

  @override
  State<_AppWithDeepLinks> createState() => _AppWithDeepLinksState();
}

class _AppWithDeepLinksState extends State<_AppWithDeepLinks> {
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

class CarzoApp extends StatelessWidget {
  const CarzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final List<SingleChildWidget> providers = buildAppProviders();
    final routes = buildAppRoutes();

    return MultiProvider(
      providers: providers,
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) {
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return _AppWithDeepLinks(
                child: MaterialApp(
                  navigatorKey: appNavigatorKey,
                  title: 'CARZO',
                  debugShowCheckedModeBanner: false,
                  builder: (context, child) => EdgeSwipeBack(
                    navigatorKey: appNavigatorKey,
                    child: child ?? const SizedBox.shrink(),
                  ),
                  theme: AppThemes.lightTheme,
                  darkTheme: AppThemes.darkTheme,
                  themeMode: themeProvider.themeMode,
                  locale: locale,
                  localizationsDelegates: const [
                    ...AppLocalizations.localizationsDelegates,
                    KuMaterialLocalizationsDelegate(),
                    KuWidgetsLocalizationsDelegate(),
                    KuCupertinoLocalizationsDelegate(),
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
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
              );
            },
          );
        },
      ),
    );
  }
}
