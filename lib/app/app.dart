import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../pages/analytics_page.dart';
import '../pages/edit_profile_page.dart';
import '../shared/i18n/ku_delegates.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';
import 'providers.dart';
import 'routes.dart';

class CarzoApp extends StatelessWidget {
  const CarzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildAppProviders(),
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.currentLocale,
        builder: (context, locale, _) {
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return MaterialApp(
                title: 'CARZO',
                locale: locale,
                supportedLocales: const [
                  Locale('en'),
                  Locale('ar'),
                  Locale('ku'),
                ],
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  KuMaterialLocalizationsDelegate(),
                  KuWidgetsLocalizationsDelegate(),
                  KuCupertinoLocalizationsDelegate(),
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
                routes: buildAppRoutes(),
              );
            },
          );
        },
      ),
    );
  }
}
