import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// U-03: Arabic/Kurdish relative-time strings ("N days/hours/minutes ago")
/// must use ICU plural forms, not bare `{count}` interpolation. English
/// already used ICU plurals; this locks in the fix for ar/ku so it can't
/// silently regress back to grammatically-wrong bare interpolation (e.g.
/// the Arabic equivalent of "1 days ago").
void main() {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final ku = lookupAppLocalizations(const Locale('ku'));

  group('U-03 timeDaysAgo (Arabic)', () {
    test('0 days uses the explicit "zero" CLDR category', () {
      // Arabic CLDR defines a distinct `zero` category (n = 0). Without it,
      // `Intl.pluralLogic` would fall through to the `other` category for
      // count 0, which happens to look the same here but must not be a
      // silent coincidence - the `zero` branch has to actually be present
      // in the ARB source.
      expect(ar.timeDaysAgo(0), 'قبل 0 يوم');
    });

    test('1 day uses the singular form, not "1 يوم"', () {
      expect(ar.timeDaysAgo(1), 'قبل يوم');
    });

    test('2 days uses the dual form', () {
      expect(ar.timeDaysAgo(2), 'قبل يومين');
    });

    test('3-10 days uses the "few" plural form', () {
      expect(ar.timeDaysAgo(3), 'قبل 3 أيام');
      expect(ar.timeDaysAgo(10), 'قبل 10 أيام');
    });

    test('11+ days uses the "many" plural form', () {
      expect(ar.timeDaysAgo(11), 'قبل 11 يوماً');
    });
  });

  group('U-03 timeHoursAgo / timeMinutesAgo (Arabic)', () {
    test('0 hours / 0 minutes use the explicit "zero" CLDR category', () {
      expect(ar.timeHoursAgo(0), 'قبل 0 ساعة');
      expect(ar.timeMinutesAgo(0), 'قبل 0 دقيقة');
    });

    test('1 hour / 1 minute use singular forms', () {
      expect(ar.timeHoursAgo(1), 'قبل ساعة');
      expect(ar.timeMinutesAgo(1), 'قبل دقيقة');
    });

    test('2 hours / 2 minutes use dual forms', () {
      expect(ar.timeHoursAgo(2), 'قبل ساعتين');
      expect(ar.timeMinutesAgo(2), 'قبل دقيقتين');
    });

    test('5 hours / 5 minutes use the "few" plural form', () {
      expect(ar.timeHoursAgo(5), 'قبل 5 ساعات');
      expect(ar.timeMinutesAgo(5), 'قبل 5 دقائق');
    });
  });

  group('U-03 daysAgo (Arabic, saved-searches wording)', () {
    test('0 days uses the explicit "zero" CLDR category', () {
      expect(ar.daysAgo(0), 'منذ 0 يوم');
    });

    test('no longer renders the wrong "1 أيام" bare-interpolation form', () {
      // The original bug: bare `{count}` interpolation always used the
      // plural noun, so 1 day rendered as the equivalent of "1 days ago".
      expect(ar.daysAgo(1), isNot(contains('1 أيام')));
      expect(ar.daysAgo(1), 'منذ يوم');
    });

    test('2-6 day range (the range this call site actually uses)', () {
      expect(ar.daysAgo(2), 'منذ يومين');
      expect(ar.daysAgo(3), 'منذ 3 أيام');
      expect(ar.daysAgo(6), 'منذ 6 أيام');
    });
  });

  group('U-03 Kurdish relative time distinguishes singular vs non-singular', () {
    test('timeDaysAgo: 1 vs other', () {
      expect(ku.timeDaysAgo(1), 'پێش ڕۆژێک');
      expect(ku.timeDaysAgo(2), 'پێش 2 ڕۆژ');
      expect(ku.timeDaysAgo(5), 'پێش 5 ڕۆژ');
    });

    test('timeHoursAgo: 1 vs other', () {
      expect(ku.timeHoursAgo(1), 'پێش کاتژمێرێک');
      expect(ku.timeHoursAgo(3), 'پێش 3 کاتژمێر');
    });

    test('timeMinutesAgo: 1 vs other', () {
      expect(ku.timeMinutesAgo(1), 'پێش خولەکێک');
      expect(ku.timeMinutesAgo(9), 'پێش 9 خولەک');
    });

    test('daysAgo (saved-searches wording): 1 vs other', () {
      expect(ku.daysAgo(1), 'پێش ڕۆژێک');
      expect(ku.daysAgo(4), 'پێش 4 ڕۆژ');
    });
  });

  group('U-03 English unchanged', () {
    final en = lookupAppLocalizations(const Locale('en'));
    test('still uses its existing ICU plural forms', () {
      expect(en.timeDaysAgo(1), '1 day ago');
      expect(en.timeDaysAgo(2), '2 days ago');
      expect(en.daysAgo(1), '1 day ago');
      expect(en.daysAgo(5), '5 days ago');
    });
  });
}
