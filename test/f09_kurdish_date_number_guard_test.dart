import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:car_listing_app/shared/i18n/locale_formatting.dart';

/// F-09 remainder: `intl` has no Kurdish CLDR data, so the app routes Kurdish
/// number formatting through the shared helper and must not surface Material
/// date pickers (whose month/weekday names would fall back to English).
void main() {
  Future<String> fmt(WidgetTester t, Locale l, num v) async {
    late String out;
    await t.pumpWidget(
      Localizations(
        locale: l,
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: Builder(builder: (c) {
          out = decimalFormatterForLocale(c).format(v);
          return const SizedBox();
        }),
      ),
    );
    return out;
  }

  testWidgets('ku and ckb group digits like ar, never throw', (t) async {
    final ar = await fmt(t, const Locale('ar'), 1234567);
    expect(await fmt(t, const Locale('ku'), 1234567), ar);
    expect(await fmt(t, const Locale('ckb'), 1234567), ar);
  });

  testWidgets('en keeps comma grouping (negative control)', (t) async {
    expect(await fmt(t, const Locale('en'), 1234567), '1,234,567');
  });

  test('no analytics-style hard-coded en_US override for Kurdish in shared '
      'formatter', () {
    final s = File('lib/shared/i18n/locale_formatting.dart').readAsStringSync();
    expect(s.contains("decimalPattern('en_US')"), isFalse);
  });

  test('app does not use Material date pickers (no English month names in ku)',
      () {
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      if (s.contains('showDatePicker(') ||
          s.contains('showDateRangePicker(') ||
          s.contains('showTimePicker(')) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty,
        reason: 'ku date pickers would show English month names');
  });
}
