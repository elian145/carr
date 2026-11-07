import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-21: iOS permission prompts must be localized (en / ar / Sorani `ckb`) and
/// the Xcode project must ship the variants.

Map<String, String> parseStrings(String src) {
  final out = <String, String>{};
  final re =
      RegExp(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', multiLine: true);
  for (final m in re.allMatches(src)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

bool hasArabicScript(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final usageKeys = RegExp(r'<key>(NS\w+UsageDescription)</key>')
      .allMatches(plist)
      .map((m) => m.group(1)!)
      .toSet();

  Map<String, String> load(String lang) => parseStrings(
        File('ios/Runner/$lang.lproj/InfoPlist.strings').readAsStringSync(),
      );

  test('Info.plist declares permission keys and bundle localizations', () {
    expect(usageKeys, isNotEmpty);
    expect(plist, contains('CFBundleLocalizations'));
    for (final lang in ['en', 'ar', 'ckb']) {
      expect(plist, contains('<string>$lang</string>'),
          reason: 'CFBundleLocalizations must list $lang');
    }
  });

  for (final lang in ['en', 'ar', 'ckb']) {
    test('$lang InfoPlist.strings covers every usage key, non-empty', () {
      final strings = load(lang);
      expect(strings.keys.toSet(), equals(usageKeys));
      for (final v in strings.values) {
        expect(v.trim(), isNotEmpty);
      }
    });
  }

  test('ar and ckb strings are translated, not copies of English', () {
    final en = load('en');
    for (final lang in ['ar', 'ckb']) {
      final tr = load(lang);
      for (final k in usageKeys) {
        expect(tr[k], isNot(en[k]), reason: '$lang/$k still English');
        expect(hasArabicScript(tr[k]!), isTrue,
            reason: '$lang/$k has no Arabic-script text');
      }
    }
  });

  test('English variant has not drifted from Info.plist fallback', () {
    final en = load('en');
    for (final k in usageKeys) {
      final m = RegExp('<key>$k</key>\\s*<string>([^<]*)</string>')
          .firstMatch(plist)!;
      expect(en[k], m.group(1), reason: 'drift in $k');
    }
  });

  test('Xcode project references InfoPlist.strings variants and regions', () {
    expect(pbx, contains('InfoPlist.strings in Resources'));
    for (final lang in ['en', 'ar', 'ckb']) {
      expect(pbx, contains('path = $lang.lproj/InfoPlist.strings'));
    }
    final regions =
        RegExp(r'knownRegions = \(([^)]*)\)').firstMatch(pbx)!.group(1)!;
    for (final r in ['en', 'Base', 'ar', 'ckb']) {
      expect(RegExp('\\b$r\\b').hasMatch(regions), isTrue,
          reason: 'knownRegions missing $r');
    }
  });

  group('negative cases for the helpers', () {
    test('parseStrings ignores comments and malformed lines', () {
      final p = parseStrings('/* "A" = "x"; */\n"B" = "y";\nC = "z";\n"D" = ;');
      expect(p.keys.toList(), ['B']);
    });
    test('a missing key is detected', () {
      expect(
        parseStrings('"NSCameraUsageDescription" = "x";')
            .containsKey('NSMicrophoneUsageDescription'),
        isFalse,
      );
    });
    test('Latin text is not Arabic script', () {
      expect(hasArabicScript('Camera access'), isFalse);
      expect(hasArabicScript('الكاميرا'), isTrue);
    });
  });
}
