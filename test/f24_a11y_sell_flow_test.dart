import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:car_listing_app/features/sell/sell_media_overlay_button.dart';
import 'package:car_listing_app/theme_provider.dart';

/// F-24 (sell flow): touch targets, semantics and text contrast.
double _lin(int c) {
  final s = c / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(Color c) {
  final v = c.toARGB32();
  return 0.2126 * _lin((v >> 16) & 0xFF) +
      0.7152 * _lin((v >> 8) & 0xFF) +
      0.0722 * _lin(v & 0xFF);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('overlay button has a >=48x48 hit area and a labelled button',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SellMediaOverlayButton(
              icon: Icons.close,
              label: 'Remove',
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(SellMediaOverlayButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // A tap 20px from the centre (outside the 30px badge) still hits.
    await tester.tapAt(tester.getCenter(find.byType(SellMediaOverlayButton)) +
        const Offset(20, 20));
    expect(taps, 1);
    expect(
      tester.getSemantics(find.byType(SellMediaOverlayButton)),
      matchesSemantics(
        label: 'Remove',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    handle.dispose();
  });

  test('theme text tokens meet WCAG AA 4.5:1 on their surfaces', () {
    for (final theme in [AppThemes.lightTheme, AppThemes.darkTheme]) {
      final scheme = theme.colorScheme;
      expect(contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5));
    }
  });

  test('grey helper text used in sell flow is >= 4.5:1 on white', () {
    expect(contrast(Colors.grey[600]!, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.grey[700]!, Colors.white), greaterThanOrEqualTo(4.5));
    // Negative control: grey[500] is the value that was removed from text.
    expect(contrast(Colors.grey[500]!, Colors.white), lessThan(4.5));
  });

  test('no sell-flow Text style uses a sub-4.5:1 light grey', () {
    final re = RegExp(
      r'TextStyle\([^)]*color:\s*Colors\.grey(\[(300|400|500)\]|\.shade(300|400|500))',
    );
    final bad = <String>[];
    for (final f in Directory('lib/features/sell')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (re.hasMatch(f.readAsStringSync())) bad.add(f.path);
    }
    expect(bad, isEmpty);
  });

  test('sell thumbnails use the shared >=48dp overlay button', () {
    final raw = RegExp(
      r'InkWell\([^;]*?padding:\s*const EdgeInsets\.all\(6\)',
      dotAll: true,
    );
    for (final n in [
      'sell_step4_build_photos',
      'sell_step4_build_videos',
      'sell_step4_build_damage',
    ]) {
      final s = File('lib/features/sell/$n.dart').readAsStringSync();
      expect(raw.hasMatch(s), isFalse, reason: '$n has a sub-48dp InkWell');
      expect(s, contains('SellMediaOverlayButton'));
    }
    final photos =
        File('lib/features/sell/sell_step4_build_photos.dart').readAsStringSync();
    expect(photos, contains('a11yPhotoXOfY'));
  });
}
