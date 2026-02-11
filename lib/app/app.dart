import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../l10n/app_localizations.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';
import 'providers.dart';
import 'routes.dart';

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
              return MaterialApp(
                title: 'CARZO',
                debugShowCheckedModeBanner: false,
                theme: AppThemes.lightTheme,
                darkTheme: AppThemes.darkTheme,
                themeMode: themeProvider.themeMode,
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routes: routes,
              );
            },
          );
        },
      ),
    );
  }
}

