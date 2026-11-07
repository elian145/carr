import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:car_listing_app/shared/i18n/digits.dart';
import 'package:car_listing_app/shared/i18n/locale_formatting.dart';

/// F-09 remainder: `intl` ships no `ku`/`ckb` number data, so a raw
/// `NumberFormat.decimalPattern('ku')` throws. Every Kurdish tag the app can
/// see (`ku`, `ku_IQ`, device `ckb`, `ckb_IQ`, `ckb_Arab_IQ`) must resolve to a
/// working, consistent (Western digits, comma grouping) formatter.
void main() {
  Future<String> format(WidgetTester t, Locale locale, num value) async {
    late String out;
    await t.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Builder(
          builder: (context) {
            out = localizeDigits(
              context,
              decimalFormatterForLocale(context).format(value),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return out;
  }

  final kurdish = <Locale>[
    const Locale('ku'),
    const Locale('ku', 'IQ'),
    const Locale('ckb'),
    const Locale('ckb', 'IQ'),
    Locale.fromSubtags(
      languageCode: 'ckb',
      scriptCode: 'Arab',
      countryCode: 'IQ',
    ),
  ];

  for (final locale in kurdish) {
    testWidgets('decimal formatter works for $locale', (t) async {
      expect(await format(t, locale, 1234567), '1,234,567');
      expect(await format(t, locale, 0), '0');
      expect(await format(t, locale, 25000.5), '25,000.5');
    });
  }

  testWidgets('Kurdish output matches Arabic and English (no mixed digits)',
      (t) async {
    final en = await format(t, const Locale('en'), 98765432);
    final ar = await format(t, const Locale('ar'), 98765432);
    final ku = await format(t, const Locale('ku'), 98765432);
    expect(ku, en);
    expect(ku, ar);
    expect(RegExp(r'[\u0660-\u0669\u06F0-\u06F9]').hasMatch(ku), isFalse,
        reason: 'Arabic-Indic digits would contradict localizeDigits');
  });

  testWidgets('unknown locale falls back to English instead of throwing',
      (t) async {
    expect(await format(t, const Locale('xx'), 1234), '1,234');
  });
}
