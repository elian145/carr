import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-21: iOS permission descriptions must be localized (ar + Sorani `ckb`)
/// and the Xcode project must actually ship the variants.
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  final usageKeys = RegExp(r'<key>(NS\w+UsageDescription)</key>')
      .allMatches(plist)
      .map((m) => m.group(1)!)
      .toSet();

  Map<String, String> parse(String lang) {
    final text = File('ios/Runner/$lang.lproj/InfoPlist.strings')
        .readAsStringSync();
    return {
      for (final m
          in RegExp(r'^"(\w+)"\s*=\s*"(.+)";\s*$', multiLine: true)
              .allMatches(text))
        m.group(1)!: m.group(2)!,
    };
  }

  test('Info.plist declares permission keys and bundle localizations', () {
    expect(usageKeys, isNotEmpty);
    for (final lang in ['en', 'ar', 'ckb']) {
      expect(plist, contains('<string>$lang</string>'),
          reason: 'CFBundleLocalizations must list $lang');
    }
  });

  for (final lang in ['en', 'ar', 'ckb']) {
    test('$lang InfoPlist.strings covers every usage key, non-empty', () {
      final strings = parse(lang);
      expect(strings.keys.toSet(), equals(usageKeys));
      for (final v in strings.values) {
        expect(v.trim(), isNotEmpty);
      }
    });
  }

  test('ar and ckb strings are translated, not copies of English', () {
    final en = parse('en');
    for (final lang in ['ar', 'ckb']) {
      final tr = parse(lang);
      for (final k in usageKeys) {
        expect(tr[k], isNot(en[k]), reason: '$lang/$k still English');
        expect(RegExp(r'[\u0600-\u06FF]').hasMatch(tr[k]!), isTrue,
            reason: '$lang/$k has no Arabic-script text');
      }
    }
  });

  test('Xcode project references InfoPlist.strings variants and regions', () {
    expect(pbx, contains('InfoPlist.strings in Resources'));
    for (final lang in ['en', 'ar', 'ckb']) {
      expect(pbx, contains('path = $lang.lproj/InfoPlist.strings'));
    }
    final regions = RegExp(r'knownRegions = \(([^)]*)\)')
        .firstMatch(pbx)!
        .group(1)!;
    for (final r in ['en', 'Base', 'ar', 'ckb']) {
      expect(regions, contains(r));
    }
  });
}
