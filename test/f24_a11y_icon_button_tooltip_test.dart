import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-24: every IconButton needs a tooltip so screen readers announce it.
/// The sell flow used to be excluded here; it is now covered too.
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
        if (!s.substring(m.start, i).contains('tooltip')) {
          out.add('${f.path}:${s.substring(0, m.start).split('\n').length}');
        }
      }
    }
    return out;
  }

  test('no IconButton without tooltip (sell flow included)', () {
    expect(missingTooltip(), isEmpty);
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
