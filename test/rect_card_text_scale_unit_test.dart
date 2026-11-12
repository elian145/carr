// Pure-math contracts behind the fixed-height rectangular listing card:
//  * the list cell keeps its 1.0x height at every system text scale,
//  * the two-column grid cell is exactly what it was (recorded values),
//  * the text scale the card text may use is derived from the fixed height
//    (~1.5x Pro Max, ~1.3x 393 dp, ~1.15-1.2x 360 dp and below),
//  * the flex-with-minimums resolver that lays out the card's text column.
import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

double _listHeight(double w, double s) =>
    (w - 8) / ListingLayoutPrefs.gridChildAspectRatioForWidth(1, w, textScale: s);

void main() {
  group('list cell height does not depend on the text scale', () {
    for (final w in const [320.0, 360.0, 393.0, 440.0, 820.0]) {
      test('${w}dp', () {
        final base = _listHeight(w, 1.0);
        for (final s in const [1.0, 1.15, 1.3, 1.5, 2.0, 3.0]) {
          expect(_listHeight(w, s), closeTo(base, 1e-9), reason: '${w}dp @${s}x');
        }
      });
    }
    test('1.0x heights are the ones the app always had', () {
      expect(_listHeight(440, 1.0), closeTo(169.41, 0.01));
      expect(_listHeight(393, 1.0), closeTo(150.98, 0.01));
      expect(_listHeight(360, 1.0), closeTo(143.67, 0.01));
      expect(_listHeight(320, 1.0), closeTo(135.65, 0.01));
    });
  });

  group('two-column grid cell', () {
    // 1.0x: exactly what the app always had (values recorded at 28de763).
    final ratios1 = <double, double>{320: 0.61, 360: 0.61, 393: 0.62, 440: 0.64, 820: 0.64};
    ratios1.forEach((w, expected) {
      test('${w}dp @1.0x ratio is unchanged', () {
        expect(
          ListingLayoutPrefs.gridChildAspectRatioForWidth(2, w, textScale: 1.0),
          closeTo(expected, 1e-9),
        );
      });
    });
    test('text block @1.0x is unchanged (150 / compact 136)', () {
      expect(ListingLayoutPrefs.gridCardTextBlockHeightAt(1.0), 150);
      expect(
        ListingLayoutPrefs.gridCardTextBlockHeightAt(1.0, compact: true),
        136,
      );
    });
    // Above 1.0x the cell grows by the content's growth: 93 dp per scale step
    // (89 compact) minus the 28 dp price footer, which now stays 26-28 dp.
    for (final s in const [1.15, 1.3, 1.5, 2.0]) {
      test('text block @${s}x = base + 65 x (scale - 1)', () {
        expect(
          ListingLayoutPrefs.gridCardTextBlockHeightAt(s),
          closeTo(150 + 65 * (s - 1), 1e-9),
        );
        expect(
          ListingLayoutPrefs.gridCardTextBlockHeightAt(s, compact: true),
          closeTo(136 + 61 * (s - 1), 1e-9),
        );
      });
    }
    test('the grid cell still gets taller as the text grows', () {
      for (final w in const [320.0, 360.0, 393.0, 440.0]) {
        var last = ListingLayoutPrefs.gridChildAspectRatioForWidth(2, w);
        for (final s in const [1.15, 1.3, 1.5, 2.0]) {
          final r = ListingLayoutPrefs.gridChildAspectRatioForWidth(
            2,
            w,
            textScale: s,
          );
          expect(r, lessThan(last), reason: '${w}dp @${s}x');
          last = r;
        }
      }
    });
  });
  group('rectCardTextScale (text scale the fixed card can hold)', () {
    double cap(double w, double s) => ListingLayoutPrefs.rectCardTextScale(
      cardHeight: _listHeight(w, 1.0),
      compact: w < 360,
      textScale: s,
    );

    test('no growth at or below 1.0x', () {
      for (final w in const [320.0, 360.0, 393.0, 440.0]) {
        expect(cap(w, 1.0), 1.0);
        expect(cap(w, 0.8), 1.0);
      }
    });

    test('Pro Max 440 dp: ~1.5x', () {
      expect(cap(440, 1.3), closeTo(1.3, 1e-9));
      expect(cap(440, 1.5), closeTo(1.5, 1e-9));
      expect(cap(440, 2.0), closeTo(1.5, 1e-9));
    });

    test('393 dp: ~1.3x', () {
      expect(cap(393, 1.15), closeTo(1.15, 1e-9));
      expect(cap(393, 2.0), inInclusiveRange(1.25, 1.3));
    });

    test('360 dp and 320 dp: ~1.15-1.2x', () {
      for (final w in const [360.0, 320.0]) {
        expect(cap(w, 2.0), inInclusiveRange(1.1, 1.2), reason: '${w}dp');
      }
    });

    test('never above the system scale, never below 1.0', () {
      for (final w in const [320.0, 360.0, 393.0, 440.0, 820.0]) {
        for (final s in const [1.0, 1.05, 1.15, 1.3, 1.5, 2.0]) {
          final c = cap(w, s);
          expect(c, lessThanOrEqualTo(s < 1.0 ? 1.0 : s));
          expect(c, greaterThanOrEqualTo(1.0));
          expect(c, lessThanOrEqualTo(1.5));
        }
      }
    });

    test('a taller card can hold at least as much text', () {
      var last = 0.0;
      for (var h = 100.0; h <= 400; h += 5) {
        final c = ListingLayoutPrefs.rectCardTextScale(
          cardHeight: h,
          compact: false,
          textScale: 2.0,
        );
        expect(c, greaterThanOrEqualTo(last), reason: 'height $h');
        last = c;
      }
    });

    test('content that needs the cap really fits the fixed height', () {
      // two-line title + two chip rows + footer + 6 dp of slack, at the cap.
      for (final w in const [320.0, 360.0, 393.0, 440.0]) {
        final compact = w < 360;
        final s = cap(w, 2.0);
        final chipFont = compact ? 11.0 : 13.0;
        final chipPad = compact ? 10.0 : 12.0;
        final need =
            (38.4 * s + 4) + 2 * (chipFont * s + chipPad) + 28 + 6;
        expect(
          need,
          lessThanOrEqualTo(_listHeight(w, 1.0) - 7 + 1e-9),
          reason: '${w}dp: content needs ${need.toStringAsFixed(1)} dp',
        );
      }
    });
  });

  group('rectCardSlotHeights (flex with minimums)', () {
    double sum(List<double> v) => v.fold(0.0, (a, b) => a + b);

    test('follows the weights when every minimum is satisfied', () {
      final h = ListingLayoutPrefs.rectCardSlotHeights(
        total: 130,
        weights: const [4, 3, 3, 3],
        mins: const [10, 10, 10, 10],
      );
      expect(h, [40.0, 30.0, 30.0, 30.0]);
    });

    test('a slot that would be too small is raised to its minimum', () {
      final h = ListingLayoutPrefs.rectCardSlotHeights(
        total: 130,
        weights: const [4, 3, 3, 3],
        mins: const [50, 10, 10, 10],
      );
      expect(h[0], 50.0);
      expect(sum(h), closeTo(130, 1e-9));
      // the rest share what is left in the ratio 3:3:3
      expect(h[1], closeTo(26.6667, 1e-3));
      expect(h[2], closeTo(h[1], 1e-9));
      expect(h[3], closeTo(h[1], 1e-9));
    });

    test('always fills the total and honours the minimums when possible', () {
      for (var total = 100.0; total <= 260; total += 7) {
        final h = ListingLayoutPrefs.rectCardSlotHeights(
          total: total,
          weights: const [4, 3, 3, 3],
          mins: const [44, 27, 27, 28],
        );
        expect(sum(h), closeTo(total, 1e-9), reason: 'total $total');
        if (total >= 44 + 27 + 27 + 28) {
          expect(h[0], greaterThanOrEqualTo(44 - 1e-9));
          expect(h[1], greaterThanOrEqualTo(27 - 1e-9));
          expect(h[2], greaterThanOrEqualTo(27 - 1e-9));
          expect(h[3], greaterThanOrEqualTo(28 - 1e-9));
        }
      }
    });

    test('impossible minimums are scaled down, never negative', () {
      final h = ListingLayoutPrefs.rectCardSlotHeights(
        total: 60,
        weights: const [4, 3, 3, 3],
        mins: const [44, 27, 27, 28],
      );
      expect(sum(h), closeTo(60, 1e-9));
      for (final v in h) {
        expect(v, greaterThan(0));
      }
    });
  });
}
