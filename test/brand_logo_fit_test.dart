import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 11 brands whose logos used to render badly inside the round pickers.
const Map<String, String> kFixedBrands = {
  'BAW': 'baw',
  'Forthing': 'forthing',
  'Hyptec': 'hyptec',
  'Ineos': 'ineos',
  'JAECOO': 'jaecoo',
  'Jonway': 'jonway',
  'Karry': 'karry',
  'Kawasaki': 'kawasaki',
  'POER': 'poer',
  'Polaris': 'polaris',
  'Vanderhall': 'vanderhall',
};

const Map<String, String> kUnaffectedBrands = {
  'Toyota': 'toyota',
  'BMW': 'bmw',
  'Mercedes-Benz': 'mercedes-benz',
  'Honda': 'honda',
  'Ford': 'ford',
};

class _Rgba {
  _Rgba(this.w, this.h, this.px);
  final int w;
  final int h;
  final Uint8List px; // straight RGBA
  int a(int x, int y) => px[(y * w + x) * 4 + 3];
  double luminance(int x, int y) {
    double c(int v) {
      final s = v / 255.0;
      return s <= 0.03928
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    final i = (y * w + x) * 4;
    return 0.2126 * c(px[i]) + 0.7152 * c(px[i + 1]) + 0.0722 * c(px[i + 2]);
  }
}

Future<_Rgba> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return _Rgba(img.width, img.height, data!.buffer.asUint8List());
}

({int x0, int y0, int x1, int y1})? _alphaBounds(_Rgba im, {int floor = 10}) {
  var x0 = im.w, y0 = im.h, x1 = -1, y1 = -1;
  for (var y = 0; y < im.h; y++) {
    for (var x = 0; x < im.w; x++) {
      if (im.a(x, y) > floor) {
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x > x1) x1 = x;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return (x0: x0, y0: y0, x1: x1 + 1, y1: y1 + 1);
}

/// Mean WCAG contrast (against a white tile) of the logo's silhouette edge:
/// opaque pixels that touch transparency. A logo whose outline is white/very
/// light (e.g. Vanderhall's white wordmark, Karry's #D8D8D8 letters) scores
/// ~1.5; anything readable on white scores well above 2.5.
double _edgeContrastOnWhite(_Rgba im) {
  const r = 2;
  var n = 0;
  var sum = 0.0;
  for (var y = 0; y < im.h; y++) {
    for (var x = 0; x < im.w; x++) {
      if (im.a(x, y) < 128) continue;
      var touchesTransparent = false;
      for (var dy = -r; dy <= r && !touchesTransparent; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= im.w || ny >= im.h) {
            touchesTransparent = true;
            break;
          }
          if (im.a(nx, ny) < 40) {
            touchesTransparent = true;
            break;
          }
        }
      }
      if (!touchesTransparent) continue;
      n++;
      sum += 1.05 / (im.luminance(x, y) + 0.05);
    }
  }
  return n == 0 ? 0 : sum / n;
}

Future<_Rgba> _renderOnBackground(
  WidgetTester tester,
  Widget child,
  Color background,
  Size size, {
  double pixelRatio = 4,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: background,
            width: size.width,
            height: size.height,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    ),
  );
  // Let Image.asset resolve + decode (needs real async), then repaint.
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(RepaintBoundary).first);
    for (final img in find.byType(Image).evaluate()) {
      final provider = (img.widget as Image).image;
      await precacheImage(provider, ctx);
    }
  });
  await tester.pump();
  late _Rgba out;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    out = _Rgba(image.width, image.height, data!.buffer.asUint8List());
  });
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shipped logo files', () {
    for (final e in kFixedBrands.entries) {
      final slug = e.value;

      test('${e.key}: bundled + backend copies exist, are identical PNGs', () {
        final backend = File('kk/static/images/brands/$slug.png');
        final bundled = File(brandLogoAssetPath(slug));
        expect(backend.existsSync(), isTrue, reason: backend.path);
        expect(bundled.existsSync(), isTrue, reason: bundled.path);
        final a = backend.readAsBytesSync();
        final b = bundled.readAsBytesSync();
        expect(a, equals(b), reason: 'backend and bundled copies must match');
        expect(a.sublist(0, 8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        expect(
          kBundledBrandLogoSlugs,
          contains(slug),
          reason: 'must be bundled so a stale network-cache copy cannot win',
        );
      });

      testWidgets(
        '${e.key}: transparent, tightly cropped, readable on a white coin',
        (tester) async {
          late _Rgba im;
          await tester.runAsync(() async {
            im = await _decode(
              File('kk/static/images/brands/$slug.png').readAsBytesSync(),
            );
          });

          // Longest side normalised so every logo has the same pixel budget.
          expect(math.max(im.w, im.h), 256);

          // No rectangular matte: all four corners and the outer 1px ring are
          // fully transparent.
          expect(im.a(0, 0), 0);
          expect(im.a(im.w - 1, 0), 0);
          expect(im.a(0, im.h - 1), 0);
          expect(im.a(im.w - 1, im.h - 1), 0);
          var ringOpaque = 0;
          for (var x = 0; x < im.w; x++) {
            if (im.a(x, 0) > 0) ringOpaque++;
            if (im.a(x, im.h - 1) > 0) ringOpaque++;
          }
          for (var y = 0; y < im.h; y++) {
            if (im.a(0, y) > 0) ringOpaque++;
            if (im.a(im.w - 1, y) > 0) ringOpaque++;
          }
          expect(
            ringOpaque,
            0,
            reason: 'artwork must not touch the canvas edge',
          );

          // Tight crop: no excessive canvas padding along the long axis.
          final b = _alphaBounds(im)!;
          final longArt = math.max(b.x1 - b.x0, b.y1 - b.y0);
          expect(longArt / 256, greaterThanOrEqualTo(0.9));

          // Contrast of the silhouette against the always-white coin.
          expect(
            _edgeContrastOnWhite(im),
            greaterThanOrEqualTo(2.5),
            reason: '${e.key} outline is too light for a white tile',
          );
        },
      );
    }

    testWidgets('Vanderhall is the emblem (shield), not the white wordmark', (
      tester,
    ) async {
      late _Rgba im;
      await tester.runAsync(() async {
        im = await _decode(
          File('kk/static/images/brands/vanderhall.png').readAsBytesSync(),
        );
      });
      final b = _alphaBounds(im)!;
      final aspect = (b.x1 - b.x0) / (b.y1 - b.y0);
      expect(
        aspect,
        lessThan(1.3),
        reason: 'wide white lock-up must not return',
      );
    });
  });

  group('BrandLogoCircle fit and clipping', () {
    for (final e in kFixedBrands.entries) {
      testWidgets('${e.key}: fits inside the circle, aspect preserved', (
        tester,
      ) async {
        const size = 52.0;
        const ratio = 4.0;
        late _Rgba art;
        await tester.runAsync(() async {
          art = await _decode(
            File(brandLogoAssetPath(e.value)).readAsBytesSync(),
          );
        });
        final ab = _alphaBounds(art, floor: 40)!;
        final artAspect = (ab.x1 - ab.x0) / (ab.y1 - ab.y0);

        // Black page: anything painted outside the circle would be visible
        // as a non-black pixel.
        final img = await _renderOnBackground(
          tester,
          BrandLogoCircle(brand: e.key, size: size),
          Colors.black,
          const Size(80, 80),
          pixelRatio: ratio,
        );

        final cx = img.w / 2, cy = img.h / 2;
        final rim = size / 2 * ratio;
        var minX = img.w, minY = img.h, maxX = -1, maxY = -1;
        var maxContentR = 0.0;
        for (var y = 0; y < img.h; y++) {
          for (var x = 0; x < img.w; x++) {
            final i = (y * img.w + x) * 4;
            final r = img.px[i], g = img.px[i + 1], b = img.px[i + 2];
            final d = math.sqrt(
              math.pow(x + .5 - cx, 2) + math.pow(y + .5 - cy, 2),
            );
            if (d > rim + 1.5) {
              // Outside the coin (+AA slack): must still be page black.
              expect(
                r + g + b,
                0,
                reason: 'pixel ($x,$y) painted outside the circle',
              );
              continue;
            }
            // Logo pixel = noticeably non-white, inside the coin interior.
            final nonWhite = (255 * 3 - (r + g + b)) > 90;
            if (nonWhite && d < rim - 2.5 * ratio) {
              minX = math.min(minX, x);
              minY = math.min(minY, y);
              maxX = math.max(maxX, x);
              maxY = math.max(maxY, y);
              maxContentR = math.max(maxContentR, d);
            }
          }
        }
        expect(maxX, greaterThan(minX), reason: 'logo not rendered at all');
        final w = (maxX - minX + 1) / ratio;
        final h = (maxY - minY + 1) / ratio;

        // Visible and comfortably sized (dp).
        expect(math.max(w, h), greaterThanOrEqualTo(27));
        // Complete: farthest logo pixel keeps >= 4 dp from the rim.
        expect(
          maxContentR / ratio,
          lessThanOrEqualTo(size / 2 - 4),
          reason: '${e.key} too close to / beyond the circle edge',
        );
        // Not distorted: rendered aspect equals the artwork aspect.
        final renderedAspect = w / h;
        expect(
          renderedAspect / artAspect,
          closeTo(1.0, 0.12),
          reason: '${e.key} aspect $renderedAspect vs artwork $artAspect',
        );
      });
    }

    test(
      'fill table keeps the artwork >= 5 dp from the rim of a 52 dp coin',
      () async {
        for (final entry in kBrandLogoCircleFill.entries) {
          final bytes = File(
            'kk/static/images/brands/${entry.key}.png',
          ).readAsBytesSync();
          final art = await _decode(bytes);
          final b = _alphaBounds(art, floor: 40)!;
          final aspect = (b.x1 - b.x0) / (b.y1 - b.y0);
          const d = 52.0;
          final box = entry.value * d; // square box, BoxFit.contain
          final s = box / math.max(art.w, art.h);
          // Farthest corner of the ink bounding box from the coin centre.
          var corner = 0.0;
          for (final x in [b.x0, b.x1]) {
            for (final y in [b.y0, b.y1]) {
              final dx = (x - art.w / 2) * s, dy = (y - art.h / 2) * s;
              corner = math.max(corner, math.sqrt(dx * dx + dy * dy));
            }
          }
          expect(
            corner,
            lessThanOrEqualTo(d / 2 - 5),
            reason:
                '${entry.key}: ink corner ${corner.toStringAsFixed(1)} dp from centre',
          );
          // Wide wordmarks are allowed to grow, never shrink, versus the
          // standard 36 dp box.
          expect(
            aspect,
            greaterThan(1.6),
            reason: '${entry.key} is not a wordmark',
          );
          expect(box, greaterThan(36));
        }
      },
    );

    testWidgets('unaffected brands keep the original 8 dp padding', (
      tester,
    ) async {
      for (final e in kUnaffectedBrands.entries) {
        final circle = BrandLogoCircle(brand: e.key, size: 52, padding: 8);
        expect(circle.insetFor(e.key), 8, reason: e.key);
        expect(
          kBundledBrandLogoSlugs.contains(e.value),
          isFalse,
          reason: e.key,
        );
        expect(
          kBrandLogoCircleFill.containsKey(e.value),
          isFalse,
          reason: e.key,
        );
      }
      // jetour/soueast were already bundled; they must stay bundled.
      expect(kBundledBrandLogoSlugs, containsAll(['jetour', 'soueast']));
    });

    testWidgets('coin is clipped to a circle and stays white in dark theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Center(child: BrandLogoCircle(brand: 'Vanderhall')),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(BrandLogoCircle),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
      final deco = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(BrandLogoCircle),
          matching: find.byType(DecoratedBox),
        ),
      );
      final bd = deco.decoration as BoxDecoration;
      expect(bd.shape, BoxShape.circle);
      expect(bd.color, Colors.white);
    });
  });

  group('image loading / cache behaviour', () {
    testWidgets(
      're-cut logos load from the bundled asset, never the network cache',
      (tester) async {
        for (final e in kFixedBrands.entries) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: BrandLogoImage(brand: e.key)),
            ),
          );
          expect(find.byType(CachedNetworkImage), findsNothing, reason: e.key);
          final image = tester.widget<Image>(find.byType(Image));
          expect(
            image.fit,
            BoxFit.contain,
            reason: '${e.key} must not stretch',
          );
          expect(
            (image.image as AssetImage).assetName,
            brandLogoAssetPath(e.value),
          );
        }
      },
    );

    testWidgets('bundled logos decode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final e in kFixedBrands.entries)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: BrandLogoImage(brand: e.key),
                  ),
              ],
            ),
          ),
        ),
      );
      final ctx = tester.element(find.byType(Scaffold));
      await tester.runAsync(() async {
        for (final e in kFixedBrands.entries) {
          await precacheImage(AssetImage(brandLogoAssetPath(e.value)), ctx);
        }
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.directions_car), findsNothing);
    });

    test(
      'network URL for a re-cut brand is unchanged (older apps keep working)',
      () {
        expect(
          brandLogoNetworkUrl('Vanderhall'),
          endsWith('/static/images/brands/vanderhall.png'),
        );
      },
    );
  });
}
