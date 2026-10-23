// Actual-size screenshots of the production "Search Cars" brand picker at the
// Samsung A17 viewport (1080 x 2340 px, devicePixelRatio 2.8125).
//
// Not a normal test: only runs when BRAND_PICKER_SHOT_DIR is set.
//
//   $env:BRAND_PICKER_SHOT_DIR = 'D:\out'
//   $env:BRAND_PICKER_SHOT_TAG = 'after'     # file prefix, default "shot"
//   flutter test test/brand_picker_screenshots_test.dart
//
// For every brand in [_focus] it writes a full-frame PNG plus a manifest CSV
// with the brand tile's rectangle (dp) so crops can be cut out afterwards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_server.dart';
import 'support/brand_picker_harness.dart';

const _focus = <String>[
  'BAW',
  'JAECOO',
  'Polaris',
  'Huanghai',
  'KAWEI',
  'Polarsun',
  'XEV',
  'Zimmer',
  'Zyle Daewoo Commercial Vehicle',
  'Renault Samsung Motors',
  'Karry',
  'Vanderhall',
  'Hyptec',
  'POER',
  'Toyota',
  'Ineos',
  'Kawasaki',
  'Forthing',
  'Jonway',
  'Bentley',
];

void main() {
  final dir = Platform.environment['BRAND_PICKER_SHOT_DIR'];
  final tag = Platform.environment['BRAND_PICKER_SHOT_TAG'] ?? 'shot';
  final bool skip = dir == null || dir.isEmpty;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });
  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  for (final light in [true, false]) {
    final theme = light ? 'light' : 'dark';
    testWidgets('screenshots $theme', (tester) async {
      final out = Directory(dir!)..createSync(recursive: true);
      await loadRoboto(tester);
      final key = GlobalKey();
      await pumpSearchBrandPicker(tester, boundaryKey: key, light: light);

      final manifest = StringBuffer();
      for (final brand in _focus) {
        final coin = await revealBrand(tester, brand);
        final tile = tester.getRect(
          find.ancestor(of: coin, matching: find.byType(InkWell)).first,
        );
        manifest.writeln(
          '$brand,${tile.left},${tile.top},${tile.right},${tile.bottom}',
        );
        final bytes = await shot(tester, key);
        final safe = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
        File('${out.path}/${tag}_${theme}_$safe.png').writeAsBytesSync(bytes);
      }
      File(
        '${out.path}/${tag}_${theme}_manifest.csv',
      ).writeAsStringSync(manifest.toString());
    }, skip: skip);
  }
}
