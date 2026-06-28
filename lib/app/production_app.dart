import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../chat_ui_theme_controller.dart';
import '../features/comparison/state/car_comparison_store.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../theme_provider.dart';
import '../shared/ui/responsive.dart';
import '../navigation/app_page_route.dart';
import '../widgets/edge_swipe_back.dart';
import 'carzo_shared.dart';
import 'route_registry.dart';
import 'production_routes.dart';
import 'widgets/app_with_deep_links.dart';

export 'carzo_shared.dart'
    show
        AuthGuard,
        buildGlobalCarCard,
        mapListingToGlobalCarCardData,
        buildLegacyFallbackRoutes;
export 'widgets/main_shell_navigation.dart'
    show buildFloatingBottomNav, navigateMainShellTab;

/// Production app shell (`lib/main.dart` entry).
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => ChatUiThemeController()),
        ChangeNotifierProvider(create: (context) => CarComparisonStore()),
        ChangeNotifierProvider.value(value: AuthService()),
      ],
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) => Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
          final routes = buildProductionRoutes();
          registerAppRoutes(routes);
          return AppWithDeepLinks(
            navigatorKey: productionNavigatorKey,
            child: MaterialApp(
              navigatorKey: productionNavigatorKey,
              title: 'CarNet',
              builder: (context, child) {
                final shellColor = Theme.of(context).scaffoldBackgroundColor;
                return AppResponsive.wrapApp(
                  context,
                  ColoredBox(
                    color: shellColor,
                    child: EdgeSwipeBack(
                      navigatorKey: productionNavigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                );
              },
              locale: locale,
              supportedLocales: const [
                Locale('en'),
                Locale('ar'),
                Locale('ku'),
              ],
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                const KuMaterialLocalizationsDelegate(),
                const KuWidgetsLocalizationsDelegate(),
                const KuCupertinoLocalizationsDelegate(),
              ],
              localeResolutionCallback: (deviceLocale, supported) {
                if (locale != null) return locale;
                if (deviceLocale == null) return const Locale('en');
                for (final l in supported) {
                  if (l.languageCode == deviceLocale.languageCode) return l;
                }
                return const Locale('en');
              },
              theme: AppThemes.lightTheme,
              darkTheme: AppThemes.darkTheme,
              themeMode: themeProvider.themeMode,
              debugShowCheckedModeBanner: false,
              initialRoute: '/',
              onGenerateRoute: (settings) =>
                  appOnGenerateRoute(settings, routes),
            ),
          );
        },
        ),
      ),
    );
  }
}
