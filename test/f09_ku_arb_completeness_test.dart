import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/l10n/app_localizations_ku.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-09: the Kurdish (Sorani) ARB must cover every existing English key and
/// must not contain Arabic-only letters (ي U+064A / ك U+0643) that render
/// Sorani words wrongly. (New hard-coded strings are out of scope - F-22.)
Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/app_$name.arb').readAsStringSync())
        as Map<String, dynamic>;

Iterable<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@'));

void main() {
  final en = _arb('en');
  final ku = _arb('ku');

  test('ku has exactly the English key set (nothing missing, nothing extra)', () {
    final enKeys = _messageKeys(en).toSet();
    final kuKeys = _messageKeys(ku).toSet();
    expect(enKeys.difference(kuKeys), isEmpty, reason: 'missing in ku');
    expect(kuKeys.difference(enKeys), isEmpty, reason: 'extra in ku');
  });

  test('no ku value is empty', () {
    final empty = _messageKeys(ku)
        .where((k) => (ku[k] as String).trim().isEmpty)
        .toList();
    expect(empty, isEmpty);
  });

  test('every ICU placeholder declared for en is used by the ku message', () {
    final problems = <String>[];
    for (final key in _messageKeys(en)) {
      final meta = en['@$key'];
      if (meta is! Map || meta['placeholders'] is! Map) continue;
      for (final name in (meta['placeholders'] as Map).keys) {
        if (!(ku[key] as String).contains('{$name')) problems.add('$key:$name');
      }
    }
    expect(problems, isEmpty);
  });

  test('ku messages use Sorani letters, not Arabic yeh/kaf', () {
    final bad = _messageKeys(ku)
        .where((k) => RegExp('[\u064A\u0643]').hasMatch(ku[k] as String))
        .toList();
    expect(bad, isEmpty, reason: 'Arabic yeh/kaf in ku values: $bad');
  });

  test('fixed strings: value_title_clean and stepXOf5', () {
    expect(ku['value_title_clean'], 'پاک');
    expect(ku['stepXOf5'], 'هەنگاوی {step} لە ٦');
    final loc = AppLocalizationsKu();
    expect(loc.value_title_clean, 'پاک');
    expect(loc.stepXOf5(2), 'هەنگاوی 2 لە ٦');
  });
}
