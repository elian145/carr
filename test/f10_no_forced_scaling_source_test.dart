// F-10: source-level guards.
//
// 1. No content text may opt out of the system text scale. The only places
//    allowed to force a fixed scale are listed below, each with the reason it
//    must stay fixed. Adding a new `noScaling` / `linear(1.0)` /
//    `textScaleFactor: 1.0` anywhere else fails this test: either remove it or
//    justify it here.
// 2. The Android side must not override the user's font size again
//    (DisplayLock.kt used to set `config.fontScale = 1.0f`); the Kotlin change
//    cannot be unit-tested here, so it is guarded at source level.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// path (relative to repo root, forward slashes) -> (expected count, reason).
const Map<String, ({int count, String reason})> _allowed = {
  'lib/shared/ui/responsive.dart': (
    count: 1,
    reason: 'AppResponsive.fittedLabel: caption of fixed-size icon tiles '
        '(FittedBox scaleDown label next to a 52 dp coin in fixed-height rows); '
        'documented at the method.',
  ),
  'lib/pages/comparison_page_helpers.dart': (
    count: 2,
    reason: 'Comparison page header cards: AutoSizeText inside fixed-width '
        'columns of a horizontally scrolling table (not a high-traffic screen; '
        'auto-shrinks to fit). Candidate for a follow-up.',
  ),
  'lib/features/sell/sell_step4_preview_helpers.dart': (
    count: 2,
    reason: 'Legacy sell preview spec tile (_buildSpecCard): 3-across '
        'childAspectRatio 1.5 tile with AutoSizeText label/value; the live sell '
        'preview uses the shared specs grid which scales. Candidate for a '
        'follow-up.',
  ),
};

final RegExp _forced = RegExp(
  r'noScaling|withNoTextScaling|textScaleFactor:\s*1\.0\b|'
  r'TextScaler\.linear\(\s*1\.0\s*\)',
);

String _norm(String path) => path.replaceAll('\\', '/');

void main() {
  test('no forced text-scale opt-out outside the documented allow-list', () {
    final offenders = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      var count = 0;
      for (final line in entity.readAsLinesSync()) {
        final code = line.trimLeft();
        if (code.startsWith('//')) continue; // comments may mention them
        count += _forced.allMatches(line).length;
      }
      if (count > 0) offenders[_norm(entity.path)] = count;
    }

    final unexpected = <String>[];
    offenders.forEach((path, count) {
      final allowed = _allowed[path];
      if (allowed == null) {
        unexpected.add('$path has $count forced text-scale opt-out(s)');
      } else if (count != allowed.count) {
        unexpected.add(
          '$path has $count (allow-list says ${allowed.count}): ${allowed.reason}',
        );
      }
    });
    for (final path in _allowed.keys) {
      if (!offenders.containsKey(path)) {
        unexpected.add('$path no longer needs its allow-list entry - remove it');
      }
    }
    expect(unexpected, isEmpty, reason: unexpected.join('\n'));
  });

  test('the TextScaler.noScaling pattern is really detected (guard self-test)',
      () {
    expect(_forced.hasMatch('textScaler: TextScaler.noScaling,'), isTrue);
    expect(_forced.hasMatch('textScaler: const TextScaler.linear(1.0),'), isTrue);
    expect(_forced.hasMatch('textScaleFactor: 1.0,'), isTrue);
    expect(_forced.hasMatch('textScaler: TextScaler.linear(ts),'), isFalse);
    expect(_forced.hasMatch('TextScaler.linear(1.5)'), isFalse);
  });

  test('Android does not override the user font size (DisplayLock.kt)', () {
    final dir = Directory('android/app/src/main/kotlin/com/carzo/app');
    expect(dir.existsSync(), isTrue);
    // `config.fontScale = ...` (member assignment); reading it into a local
    // (`val fontScale = configuration.fontScale`) is fine.
    final assignsFontScale = RegExp(r'\.fontScale\s*=(?!=)');
    final lockedScaledDensity = RegExp(r'scaledDensity\s*=\s*density\s*$');
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.kt')) continue;
      var lineNo = 0;
      for (final line in entity.readAsLinesSync()) {
        lineNo++;
        final code = line.trim();
        if (code.startsWith('//') || code.startsWith('*') || code.startsWith('/*')) {
          continue;
        }
        expect(
          assignsFontScale.hasMatch(code),
          isFalse,
          reason: '${_norm(entity.path)}:$lineNo assigns fontScale: $code',
        );
        expect(
          lockedScaledDensity.hasMatch(code),
          isFalse,
          reason: '${_norm(entity.path)}:$lineNo pins scaledDensity to density '
              '(drops the user font scale): $code',
        );
      }
    }
  });
}
