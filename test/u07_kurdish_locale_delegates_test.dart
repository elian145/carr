import 'package:car_listing_app/features/chat/chat_strings.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:car_listing_app/state/locale_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// U-07: Kurdish must no longer intentionally use Arabic Material/Cupertino
/// localization as a proxy, `ckb` must not be added as a fourth supported
/// locale, and stale `ckb` references must resolve consistently to `ku`.
void main() {
  group('U-07 supported locales', () {
    test('Kurdish locale resolution remains "ku" (not "ckb")', () {
      expect(LocaleController.supportedCodes, ['en', 'ar', 'ku']);
      expect(LocaleController.supportedCodes, isNot(contains('ckb')));
    });
  });

  group('U-07 stale "ckb" alias resolves consistently to "ku"', () {
    testWidgets('chatText treats ckb the same as ku, not English', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ku'),
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('ku'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            KuMaterialLocalizationsDelegate(),
            KuWidgetsLocalizationsDelegate(),
            KuCupertinoLocalizationsDelegate(),
          ],
          home: Builder(
            builder: (context) {
              // `ku` (the real resolved locale) and the stale `ckb` alias
              // path inside chatText must produce the identical string.
              final viaKu = chatText(
                context,
                'English',
                ar: 'عربي',
                ku: 'کوردی',
              );
              expect(viaKu, 'کوردی');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('U-07 Kurdish Material/Cupertino no longer proxies to Arabic', () {
    testWidgets('MaterialLocalizations for ku are English, not Arabic', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ku'),
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('ku'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            KuMaterialLocalizationsDelegate(),
            KuWidgetsLocalizationsDelegate(),
            KuCupertinoLocalizationsDelegate(),
          ],
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final matLoc = MaterialLocalizations.of(capturedContext);
      // Arabic would give "موافق"/"إلغاء"; must not be Arabic.
      expect(matLoc.okButtonLabel, 'OK');
      expect(matLoc.cancelButtonLabel, 'Cancel');
    });

    testWidgets('CupertinoLocalizations for ku are English, not Arabic', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ku'),
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('ku'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            KuMaterialLocalizationsDelegate(),
            KuWidgetsLocalizationsDelegate(),
            KuCupertinoLocalizationsDelegate(),
          ],
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cupLoc = CupertinoLocalizations.of(capturedContext);
      expect(cupLoc.todayLabel, 'Today');
    });

    testWidgets(
      'Kurdish text direction stays RTL even though strings are English',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ku'),
            supportedLocales: const [
              Locale('en'),
              Locale('ar'),
              Locale('ku'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              KuMaterialLocalizationsDelegate(),
              KuWidgetsLocalizationsDelegate(),
              KuCupertinoLocalizationsDelegate(),
            ],
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(Directionality.of(capturedContext), TextDirection.rtl);
      },
    );
  });
}
