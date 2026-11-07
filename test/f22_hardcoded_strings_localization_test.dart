import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/pages/change_password_page.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';

/// F-22: Change Password screen and shared badges must follow the app locale.
void main() {
  Future<void> pump(WidgetTester t, Locale locale) async {
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            KuMaterialLocalizationsDelegate(),
            KuCupertinoLocalizationsDelegate(),
            KuWidgetsLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ChangePasswordPage(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final code in ['ar', 'ku']) {
    testWidgets('change password screen is localized for $code',
        (t) async {
      await pump(t, Locale(code));
      final loc = await AppLocalizations.delegate.load(Locale(code));
      expect(find.text(loc.changePasswordTitle), findsWidgets);
      expect(find.text(loc.currentPasswordLabel), findsOneWidget);
      expect(find.text(loc.newPasswordLabel), findsOneWidget);
      expect(find.text(loc.confirmNewPasswordLabel), findsOneWidget);
      // negative: no English leftovers
      expect(find.text('Change password'), findsNothing);
      expect(find.text('Current password'), findsNothing);
      expect(find.text('New password'), findsNothing);
      expect(find.text('Confirm new password'), findsNothing);

      // validation messages localized too
      await t.tap(find.byType(ElevatedButton));
      await t.pump();
      expect(find.text(loc.pleaseEnterCurrentPassword), findsOneWidget);
      expect(find.text('Please enter your current password'), findsNothing);
    });
  }

  testWidgets('english still renders English strings', (t) async {
    await pump(t, const Locale('en'));
    expect(find.text('Current password'), findsOneWidget);
  });

  test('new keys are translated in ar and ku (not English copies)', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    for (final code in ['ar', 'ku']) {
      final l = await AppLocalizations.delegate.load(Locale(code));
      for (final pair in <List<String>>[
        [en.currentPasswordLabel, l.currentPasswordLabel],
        [en.passwordChangedSuccessfully, l.passwordChangedSuccessfully],
        [en.sendingEllipsis, l.sendingEllipsis],
        [en.videoBadge, l.videoBadge],
        [en.viewDetailsButton, l.viewDetailsButton],
        [
          en.specDatabaseUnavailableRestartTheAppAfterFlutterPubGet,
          l.specDatabaseUnavailableRestartTheAppAfterFlutterPubGet,
        ],
      ]) {
        expect(pair[1], isNot(pair[0]));
        expect(pair[1].trim(), isNotEmpty);
      }
    }
  });

  test('no user-facing "flutter pub get" developer text in any locale', () {
    for (final code in ['en', 'ar', 'ku']) {
      final arb = File('lib/l10n/app_$code.arb').readAsStringSync();
      expect(arb.contains('flutter pub get'), isFalse, reason: code);
    }
  });

  test('change password page has no hard-coded English literals', () {
    final src = File('lib/pages/change_password_page.dart').readAsStringSync();
    for (final lit in [
      "'Change password'",
      "'Current password'",
      "'New password'",
      "'Confirm new password'",
      "'Passwords do not match'",
      "'Password changed successfully'",
    ]) {
      expect(src.contains(lit), isFalse, reason: lit);
    }
  });
}
