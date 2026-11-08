import 'dart:convert';
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

  test('round 2 keys are translated in ar and ku (not English copies)',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    for (final code in ['ar', 'ku']) {
      final l = await AppLocalizations.delegate.load(Locale(code));
      for (final pair in <List<String>>[
        [en.chatUserTyping('Sam'), l.chatUserTyping('Sam')],
        [en.noSpecRowForThisYear, l.noSpecRowForThisYear],
        [en.typeModelNameToSearch, l.typeModelNameToSearch],
        [en.noModelsMatchYourSearch, l.noModelsMatchYourSearch],
        [en.yourListingFallbackTitle, l.yourListingFallbackTitle],
        [en.notificationChannelChatName, l.notificationChannelChatName],
        [
          en.notificationChannelChatDescription,
          l.notificationChannelChatDescription,
        ],
        [en.notificationChannelUpdatesName, l.notificationChannelUpdatesName],
        [
          en.notificationChannelUpdatesDescription,
          l.notificationChannelUpdatesDescription,
        ],
      ]) {
        expect(pair[1], isNot(pair[0]), reason: code);
        expect(pair[1].trim(), isNotEmpty);
      }
      // The typing indicator must still carry the interpolated name.
      expect(l.chatUserTyping('Sam'), contains('Sam'));
    }
  });

  test('legacy "Carzo" brand never appears in user-visible ARB values', () {
    // Keys such as chatOnCarzo are internal identifiers (owner decision,
    // docs/OWNER_ACTIONS.md F-11); only the rendered values are asserted.
    for (final code in ['en', 'ar', 'ku']) {
      final arb = File('lib/l10n/app_$code.arb').readAsStringSync();
      final decoded = jsonDecode(arb) as Map<String, dynamic>;
      for (final e in decoded.entries) {
        final v = e.value;
        if (v is! String) continue;
        expect(RegExp(r'carzo', caseSensitive: false).hasMatch(v), isFalse,
            reason: '$code:${e.key}');
      }
    }
  });

  test('previously hard-coded literals were replaced by localized lookups',
      () {
    const removed = <String, List<String>>{
      'lib/features/chat/chat_conversation_page_build_body_composer.dart': [
        "is typing...'",
      ],
      'lib/features/sell/sell_step1_catalog.dart': [
        "'No spec row for this year",
      ],
      'lib/features/home/home_fetch.dart': [
        "'Sorting temporarily unavailable'",
      ],
      'lib/pages/analytics_page_listing_card.dart': [
        "'Analytics Dashboard'",
        "'Performance insights'",
        "'Performance Metrics'",
      ],
      'lib/shared/navigation/route_args.dart': ["Text('Navigation error')"],
      'lib/app/production_routes.dart': ["'Missing listing id'"],
      'lib/app/legacy_fallback_routes.dart': ["'Missing listing id'"],
      'lib/app/widgets/home_search_dialog.dart': [
        "'Type a model name to search",
        "'No models match your search.'",
      ],
      'lib/pages/saved_searches_page_helpers.dart': [
        "'Damaged Parts'",
        "'Accident History'",
      ],
      'lib/features/sell/sell_step4_preview_listing.dart': [
        "'Your listing'",
      ],
      'lib/services/push_notification_service.dart': [
        "'Chat messages'",
        "'Account updates'",
      ],
    };
    removed.forEach((path, literals) {
      final src = File(path).readAsStringSync();
      for (final lit in literals) {
        expect(src.contains(lit), isFalse, reason: '$path: $lit');
      }
    });
  });

  test('chat reply preview uses the localized "Message" fallback', () {
    final src = File('lib/features/chat/widgets/chat_composer_widgets.dart')
        .readAsStringSync();
    expect(src.contains("?? 'Message'"), isFalse);
    expect(src.contains(": 'Message',"), isFalse);
    expect(src.contains("? 'Message'"), isFalse);
  });}
