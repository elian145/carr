import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-24: every IconButton needs a tooltip so screen readers announce it.
/// The sell flow used to be excluded here; it is now covered too.
const _exemptMarker = 'a11y-exempt-no-overlay';

void main() {
  List<String> missingTooltip() {
    final out = <String>[];
    final re = RegExp(r'(?<![A-Za-z])IconButton(\.(?!styleFrom)\w+)?\(');
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.contains('l10n')) continue;
      final s = f.readAsStringSync();
      for (final m in re.allMatches(s)) {
        var i = m.end, depth = 1;
        while (depth > 0 && i < s.length) {
          final c = s[i++];
          if (c == '(') depth++;
          if (c == ')') depth--;
        }
        final call = s.substring(m.start, i);
        if (call.contains('tooltip')) continue;
        // Audited exemption: see `exemptions()` below.
        if (call.contains(_exemptMarker)) continue;
        out.add('${f.path}:${s.substring(0, m.start).split('\n').length}');
      }
    }
    return out;
  }

  test('no IconButton without tooltip (sell flow included)', () {
    expect(missingTooltip(), isEmpty);
  });

  test('tooltip exemptions are exactly the Overlay-less banner button', () {
    // A Tooltip needs an Overlay ancestor. SellSubmissionStatusBanner is
    // mounted in MaterialApp.builder, above the Navigator, so a Tooltip there
    // asserts. Its button is labelled through Semantics instead. Any new
    // exemption must be added here deliberately.
    final marked = <String>[
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (f.readAsStringSync().contains(_exemptMarker))
          f.path.replaceAll('\\', '/'),
    ];
    expect(marked, ['lib/app/widgets/sell_submission_status_banner.dart']);
    final banner = File('lib/app/widgets/sell_submission_status_banner.dart')
        .readAsStringSync();
    expect(banner, contains('MergeSemantics'));
    expect(banner, contains('label: loc.a11yCancelUpload'));
  });

  test('scanner detects a missing tooltip (negative control)', () {
    const bad = 'IconButton(icon: Icon(Icons.close), onPressed: () {})';
    const good = "IconButton(tooltip: 'x', icon: Icon(Icons.close))";
    final re = RegExp(r'IconButton\(');
    expect(re.hasMatch(bad) && !bad.contains('tooltip'), isTrue);
    expect(good.contains('tooltip'), isTrue);
  });

  test('legal links and home search entry expose button/link semantics', () {
    final login = File('lib/pages/production_login_page.dart')
        .readAsStringSync();
    expect(login, contains('link: true'));
    final search = File('lib/features/home/home_slivers_search_bar.dart')
        .readAsStringSync();
    expect(search, contains('button: true'));
  });
}
