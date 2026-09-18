import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// U-02: navigation/chevron icons (Icons.arrow_back, Icons.chevron_right,
/// etc.) must point in the correct reading direction for RTL locales.
///
/// This app relies on Flutter's built-in `IconData.matchTextDirection`
/// (true for arrow_back/arrow_forward/chevron_left/chevron_right and their
/// *_ios/*_rounded variants), which mirrors the icon automatically based on
/// the ambient `Directionality` -- as long as that Directionality is
/// actually RTL for ar/ku, which depends on the app's locale delegate setup
/// (see U-07's `ku_delegates.dart`). This test locks in that the app's real
/// MaterialApp locale configuration (English + Arabic + the U-07 Kurdish
/// delegates) produces correct mirroring for representative back/forward
/// icons under both LTR (English) and RTL (Arabic, Kurdish) without any
/// extra app-side RTL icon-selection code.
void main() {
  Future<bool> hasMirrorTransform(
    WidgetTester tester,
    Locale locale,
    IconData icon,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('ku')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          KuMaterialLocalizationsDelegate(),
          KuWidgetsLocalizationsDelegate(),
          KuCupertinoLocalizationsDelegate(),
        ],
        home: Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: Icon(icon), onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final transformFinder = find.descendant(
      of: find.byType(Icon),
      matching: find.byType(Transform),
    );
    return transformFinder.evaluate().isNotEmpty;
  }

  group('U-02 Icons.arrow_back mirrors for RTL', () {
    testWidgets('English (LTR): not mirrored', (tester) async {
      expect(
        await hasMirrorTransform(tester, const Locale('en'), Icons.arrow_back),
        isFalse,
      );
    });

    testWidgets('Arabic (RTL): mirrored', (tester) async {
      expect(
        await hasMirrorTransform(tester, const Locale('ar'), Icons.arrow_back),
        isTrue,
      );
    });

    testWidgets('Kurdish (RTL): mirrored', (tester) async {
      expect(
        await hasMirrorTransform(tester, const Locale('ku'), Icons.arrow_back),
        isTrue,
      );
    });
  });

  group('U-02 Icons.chevron_right mirrors for RTL', () {
    testWidgets('English (LTR): not mirrored', (tester) async {
      expect(
        await hasMirrorTransform(
          tester,
          const Locale('en'),
          Icons.chevron_right,
        ),
        isFalse,
      );
    });

    testWidgets('Arabic (RTL): mirrored', (tester) async {
      expect(
        await hasMirrorTransform(
          tester,
          const Locale('ar'),
          Icons.chevron_right,
        ),
        isTrue,
      );
    });

    testWidgets('Kurdish (RTL): mirrored', (tester) async {
      expect(
        await hasMirrorTransform(
          tester,
          const Locale('ku'),
          Icons.chevron_right,
        ),
        isTrue,
      );
    });
  });
}
