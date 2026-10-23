// Regression tests driven through the REAL "Search Cars" brand picker at the
// Samsung Galaxy A17 viewport (384 x 832 dp @ 2.8125), the layout that
// showed BAW / JAECOO / Polaris overflowing their circles on the phone while
// every isolated BrandLogoCircle test passed.
//
// Why isolated tests missed it: they gave the coin an explicit size. In the
// real tile the parent hands the coin TIGHT 70 dp width constraints, which
// turned the 52 dp coin into a 70 x 52 box (clipped to an ellipse, padding
// measured against 70 dp).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:car_listing_app/data/brand_logo_filenames.dart' show brandLogoSlug;
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:car_listing_app/shared/ui/brand_tile_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_server.dart';
import 'support/brand_picker_harness.dart';

const double _coin = 52;
const double _radius = _coin / 2;

/// Brands shown in the user's phone screenshots (and the 11 from round 1).
const _reviewed = <String>[
  'BAW',
  'Forthing',
  'Huanghai',
  'Hyptec',
  'Ineos',
  'JAECOO',
  'Jonway',
  'Karry',
  'Kawasaki',
  'KAWEI',
  'POER',
  'Polarsun',
  'Polaris',
  'Vanderhall',
  'XEV',
  'Zimmer',
  'Zyle Daewoo Commercial Vehicle',
  'Toyota',
  'BMW',
  'Mercedes-Benz',
];

class _Px {
  _Px(this.w, this.h, this.rgba);
  final int w;
  final int h;
  final Uint8List rgba;
}

Future<_Px?> _decodeLogo(String slug) async {
  final f = File('kk/static/images/brands/$slug.png');
  if (!f.existsSync()) return null;
  final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return _Px(img.width, img.height, data!.buffer.asUint8List());
}

/// Farthest distance (dp) from [center] of any VISIBLE ink pixel when [px] is
/// drawn BoxFit.contain, centred, into [box]. "Ink" = at least 25% opaque and
/// not white (white-on-white is invisible on the coin).
double _maxInkRadius(_Px px, Rect box, Offset center) {
  final s = math.min(box.width / px.w, box.height / px.h);
  final dw = px.w * s, dh = px.h * s;
  final ox = box.center.dx - dw / 2, oy = box.center.dy - dh / 2;
  var maxR = 0.0;
  for (var y = 0; y < px.h; y++) {
    for (var x = 0; x < px.w; x++) {
      final i = (y * px.w + x) * 4;
      if (px.rgba[i + 3] < 64) continue;
      if (px.rgba[i] > 240 && px.rgba[i + 1] > 240 && px.rgba[i + 2] > 240) {
        continue;
      }
      // far corner of this source pixel
      final cx = x < px.w / 2 ? x.toDouble() : x + 1.0;
      final cy = y < px.h / 2 ? y.toDouble() : y + 1.0;
      final dx = ox + cx * s - center.dx;
      final dy = oy + cy * s - center.dy;
      final r = math.sqrt(dx * dx + dy * dy);
      if (r > maxR) maxR = r;
    }
  }
  return maxR;
}

class _Measured {
  _Measured(this.brand, this.coinRect, this.tileRect, this.imageRect);
  final String brand;
  final Rect coinRect;
  final Rect tileRect;
  final Rect? imageRect; // null => generic icon fallback
}

List<_Measured> _measureVisibleCoins(WidgetTester tester) {
  final out = <_Measured>[];
  for (final e in find.byType(BrandLogoCircle).evaluate()) {
    final w = e.widget as BrandLogoCircle;
    final coinFinder = find.byWidget(w);
    final clip = find.descendant(of: coinFinder, matching: find.byType(ClipOval));
    final tile = find.ancestor(of: coinFinder, matching: find.byType(InkWell));
    if (clip.evaluate().isEmpty || tile.evaluate().isEmpty) continue;
    final img = find.descendant(of: coinFinder, matching: find.byType(Image));
    out.add(
      _Measured(
        w.brand,
        tester.getRect(clip.first),
        tester.getRect(tile.first),
        img.evaluate().isEmpty ? null : tester.getRect(img.first),
      ),
    );
  }
  return out;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });
  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'root cause: a BrandLogoCircle under tight 70 dp width (the Search tile) '
    'is still a centred 52 x 52 circle, not a 70 x 52 ellipse',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle),
                    child: BrandLogoCircle(brand: 'BAW'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final clip = tester.getRect(find.byType(ClipOval));
      expect(clip.size, const Size(_coin, _coin));
      expect(clip.center.dx, closeTo(36, 0.01), reason: 'centred in the tile');
    },
  );

  testWidgets(
    'Search Cars picker on the A17: every brand coin is a centred 52 dp '
    'circle and no visible logo pixel reaches the rim',
    (tester) async {
      final key = GlobalKey();
      await pumpSearchBrandPicker(tester, boundaryKey: key);

      final seen = <String, _Measured>{};
      final grid = find.byType(GridView).first;
      await tester.ensureVisible(grid);
      await settle(tester, frames: 2);
      for (var i = 0; i < 60; i++) {
        for (final m in _measureVisibleCoins(tester)) {
          seen.putIfAbsent(m.brand, () => m);
        }
        final before = seen.length;
        await tester.drag(grid, const Offset(0, -150));
        await settle(tester, frames: 2);
        for (final m in _measureVisibleCoins(tester)) {
          seen.putIfAbsent(m.brand, () => m);
        }
        if (i > 20 && seen.length == before) break;
      }

      expect(
        seen.keys,
        containsAll(_reviewed),
        reason: 'grid scroll did not reach every reviewed brand',
      );
      expect(seen.length, greaterThan(140));

      final problems = <String>[];
      final placeholders = <String>[];
      final radii = <String, double>{};
      await tester.runAsync(() async {
        for (final m in seen.values) {
          if (m.coinRect.size != const Size(_coin, _coin)) {
            problems.add('${m.brand}: coin is ${m.coinRect.size}, not 52 x 52');
          }
          if ((m.coinRect.center.dx - m.tileRect.center.dx).abs() > 0.5) {
            problems.add('${m.brand}: coin not centred in its tile');
          }
          if (m.imageRect == null) {
            placeholders.add(m.brand);
            continue;
          }
          final slug = brandLogoSlug(m.brand);
          final px = await _decodeLogo(slug);
          if (px == null) continue;
          final r = _maxInkRadius(px, m.imageRect!, m.coinRect.center);
          radii[m.brand] = r;
          // Never touch or cross the white circle (0.5 dp of air at least).
          if (r > _radius - 0.5) {
            problems.add(
              '${m.brand}: logo ink reaches ${r.toStringAsFixed(1)} dp '
              'from the centre (circle radius $_radius)',
            );
          }
        }
      });
      expect(problems, isEmpty, reason: problems.join('\n'));

      // Brands the user reviewed on the phone must show a real logo, not the
      // generic orange car icon (Huanghai used to).
      for (final b in _reviewed) {
        expect(
          placeholders,
          isNot(contains(b)),
          reason: '$b shows the generic car icon',
        );
      }

      // The re-cut wide wordmarks keep real breathing room (>= 5 dp).
      for (final b in const [
        'BAW',
        'Ineos',
        'JAECOO',
        'Kawasaki',
        'Polaris',
        'KAWEI',
        'Zyle Daewoo Commercial Vehicle',
      ]) {
        expect(
          radii[b]!,
          lessThanOrEqualTo(_radius - 5),
          reason: '$b is too close to the circle edge',
        );
      }
    },
  );

  testWidgets(
    'Search Cars picker on the A17: captions stay inside the 72 x 92 tile, '
    'are readable (>= 10 sp), never ellipsised, and keep four columns',
    (tester) async {
      final haveRoboto = await loadRoboto(tester);
      final key = GlobalKey();
      await pumpSearchBrandPicker(tester, boundaryKey: key);

      final grid = find.byType(GridView).first;
      await tester.ensureVisible(grid);
      await settle(tester, frames: 2);

      final labels = <String, ({double size, int lines, bool exceeded, Size box})>{};
      void collect() {
        for (final e in find.byType(BrandTileLabel).evaluate()) {
          final w = e.widget as BrandTileLabel;
          final rp = find.descendant(
            of: find.byWidget(w),
            matching: find.byType(RichText),
          );
          if (rp.evaluate().isEmpty) continue;
          final para = tester.renderObject<RenderParagraph>(rp.first);
          final style = para.text.style!;
          labels.putIfAbsent(
            w.text,
            () => (
              size: style.fontSize!,
              lines: para.maxLines ?? 1,
              exceeded: para.didExceedMaxLines,
              box: para.size,
            ),
          );
        }
      }

      for (var i = 0; i < 60; i++) {
        final before = labels.length;
        collect();
        await tester.drag(grid, const Offset(0, -150));
        await settle(tester, frames: 2);
        collect();
        if (i > 20 && labels.length == before) break;
      }
      expect(labels.length, greaterThan(140));

      // Column count of the real grid: tiles share 4 distinct x positions.
      final xs = <int>{};
      for (final e in find.byType(BrandLogoCircle).evaluate()) {
        final tile = find.ancestor(
          of: find.byWidget(e.widget),
          matching: find.byType(InkWell),
        );
        if (tile.evaluate().isNotEmpty) {
          xs.add(tester.getRect(tile.first).left.round());
        }
      }
      expect(xs.length, 4, reason: 'brand grid must stay four columns: $xs');

      if (!haveRoboto) {
        // Metrics below are only meaningful with the phone's real font.
        return;
      }
      final problems = <String>[];
      labels.forEach((text, l) {
        if (l.exceeded) problems.add('$text: ellipsised at ${l.lines} lines');
        if (l.size < 10 - 0.01) problems.add('$text: ${l.size} sp is below 10 sp');
        if (l.box.width > 72.01) problems.add('$text: wider than the tile');
        if (l.box.height > BrandTileLabel.maxHeight + 0.01) {
          problems.add('$text: ${l.box.height} dp tall');
        }
      });
      expect(problems, isEmpty, reason: problems.join('\n'));

      // The names the phone showed badly.
      final zyle = labels['Zyle Daewoo Commercial Vehicle']!;
      expect(zyle.size, greaterThanOrEqualTo(10));
      expect(zyle.lines, 3);
      // Short names are untouched: one line at the normal 12 sp.
      for (final n in const ['Toyota', 'BMW', 'Karry', 'BAW']) {
        expect(labels[n]!.size, 12, reason: n);
        expect(labels[n]!.lines, 1, reason: n);
      }
      // ...which means every short name, measured with the real font, keeps
      // the normal 12 sp (a label measured with the wrong font used to shrink
      // names like "Bentley" and "Chevrolet").
      labels.forEach((text, l) {
        if (text.length <= 9) {
          expect(l.size, 12, reason: '$text should not be shrunk');
          expect(l.lines, 1, reason: text);
        }
      });
    },
  );

  test('BrandTileLabel plan: long names wrap instead of shrinking to nothing', () {
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    final p = BrandTileLabel.plan(
      text: 'Zyle Daewoo Commercial Vehicle',
      style: style,
      maxWidth: 72,
    );
    // With the default (Ahem) test font every glyph is 1 em wide, so this only
    // asserts the contract: a legible size and the 30 dp height budget.
    expect(p.fontSize, greaterThanOrEqualTo(10));
    expect(p.maxLines, lessThanOrEqualTo(3));
    final short = BrandTileLabel.plan(text: 'Kia', style: style, maxWidth: 72);
    expect(short.fontSize, 12);
    expect(short.maxLines, 1);
  });
}
