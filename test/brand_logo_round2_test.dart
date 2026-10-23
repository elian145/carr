// Second round of brand-logo fixes (found on the physical phone): Huanghai,
// KAWEI, Polarsun, XEV, Zimmer (re-cut files) and Zyle Daewoo (fill table).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:car_listing_app/data/brand_logo_filenames.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> kRound2 = {
  'Huanghai': 'huanghai',
  'KAWEI': 'kawei',
  'Polarsun': 'polarsun',
  'XEV': 'xev',
  'Zimmer': 'zimmer',
};

class _Px {
  _Px(this.w, this.h, this.rgba);
  final int w;
  final int h;
  final Uint8List rgba;
  int a(int x, int y) => rgba[(y * w + x) * 4 + 3];
}

Future<_Px> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return _Px(img.width, img.height, data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final e in kRound2.entries) {
    final slug = e.value;

    test('${e.key}: slug maps to the shipped file', () {
      expect(brandLogoSlug(e.key), slug);
    });

    test('${e.key}: bundled + backend copies are identical PNGs and bundled', () {
      final backend = File('kk/static/images/brands/$slug.png');
      final bundled = File(brandLogoAssetPath(slug));
      expect(backend.existsSync(), isTrue, reason: backend.path);
      expect(bundled.existsSync(), isTrue, reason: bundled.path);
      expect(backend.readAsBytesSync(), bundled.readAsBytesSync());
      expect(
        kBundledBrandLogoSlugs,
        contains(slug),
        reason: 'bundled so a stale cached network copy cannot win',
      );
    });

    test('${e.key}: no rectangular matte (transparent corners, ring, tight)', () async {
      final im = await _decode(
        File('kk/static/images/brands/$slug.png').readAsBytesSync(),
      );
      expect(math.max(im.w, im.h), 256);
      expect(im.a(0, 0), 0);
      expect(im.a(im.w - 1, 0), 0);
      expect(im.a(0, im.h - 1), 0);
      expect(im.a(im.w - 1, im.h - 1), 0);
      // The artwork must not touch the canvas edge on any side.
      var edgeInk = 0;
      for (var x = 0; x < im.w; x++) {
        if (im.a(x, 0) > 10) edgeInk++;
        if (im.a(x, im.h - 1) > 10) edgeInk++;
      }
      for (var y = 0; y < im.h; y++) {
        if (im.a(0, y) > 10) edgeInk++;
        if (im.a(im.w - 1, y) > 10) edgeInk++;
      }
      expect(edgeInk, 0);
      // A white rectangle would make most of the canvas opaque.
      var opaque = 0;
      for (var i = 3; i < im.rgba.length; i += 4) {
        if (im.rgba[i] > 200) opaque++;
      }
      expect(opaque / (im.w * im.h), lessThan(0.85));
    });
  }

  test('XEV ships the COMPLETE official lock-up (X and EV), visible on white', () async {
    final im = await _decode(
      File('kk/static/images/brands/xev.png').readAsBytesSync(),
    );
    // Official light-background lock-up: blue X + grey "EV", aspect ~3.4. The
    // X-only crop (aspect ~1.3) and the dark-background lock-up (white "EV")
    // must never come back.
    expect(im.w / im.h, greaterThan(3.0), reason: 'X-only crop is back');
    // Ink must exist in the left part (blue X) AND the right part (EV), and
    // every opaque ink pixel must be clearly visible against the white coin.
    var left = 0, right = 0, faint = 0, blue = 0, grey = 0;
    for (var y = 0; y < im.h; y++) {
      for (var x = 0; x < im.w; x++) {
        final i = (y * im.w + x) * 4;
        if (im.rgba[i + 3] < 200) continue;
        final r = im.rgba[i], g = im.rgba[i + 1], b = im.rgba[i + 2];
        final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
        if (lum > 0.8) faint++; // would vanish on white
        if (x < im.w * 0.33) {
          left++;
          if (b > r + 40) blue++;
        }
        if (x > im.w * 0.42) {
          right++;
          if ((r - b).abs() < 30 && (g - b).abs() < 30) grey++;
        }
      }
    }
    final total = im.w * im.h;
    expect(left / total, greaterThan(0.08), reason: 'blue X missing');
    expect(right / total, greaterThan(0.12), reason: '"EV" lettering missing');
    expect(blue / left, greaterThan(0.9), reason: 'X is not the brand blue');
    expect(grey / right, greaterThan(0.9), reason: 'EV is not the dark-grey lettering');
    expect(faint, 0, reason: 'near-white ink would vanish on the white coin');
  });

  test('Huanghai is its own emblem, not the SG parent-group mark', () async {
    // The parent mark (red sun / blue waves with Chinese company text) was the
    // scraper's file; the brand emblem is a grey chrome ring. Guard against the
    // red/blue parent mark: the shipped emblem must be (almost) colourless.
    final im = await _decode(
      File('kk/static/images/brands/huanghai.png').readAsBytesSync(),
    );
    var coloured = 0, ink = 0;
    for (var i = 0; i < im.rgba.length; i += 4) {
      if (im.rgba[i + 3] < 128) continue;
      ink++;
      final r = im.rgba[i], g = im.rgba[i + 1], b = im.rgba[i + 2];
      if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) > 50) {
        coloured++;
      }
    }
    expect(ink, greaterThan(0));
    expect(coloured / ink, lessThan(0.05));
  });

  test('Zyle Daewoo and KAWEI are pulled inside the circle via the fill table', () {
    expect(kBrandLogoCircleFill, contains('zyle-daewoo-commercial-vehicle'));
    expect(kBrandLogoCircleFill, contains('kawei'));
    expect(kBrandLogoCircleFill, contains('xev'));
  });

  test('brands that were already correct are not in the fill table', () {
    for (final s in const [
      'karry', 'hyptec', 'poer', 'vanderhall', 'forthing', 'jonway',
      'toyota', 'bmw', 'mercedes-benz', 'honda', 'ford', 'polarsun', 'zimmer', 'huanghai',
    ]) {
      expect(kBrandLogoCircleFill.containsKey(s), isFalse, reason: s);
    }
  });
}
