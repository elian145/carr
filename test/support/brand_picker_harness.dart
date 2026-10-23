// Shared harness for tests that drive the REAL "Search Cars" brand picker
// (HomePage.searchFilters -> _searchMakeSection -> _searchBrandTile) at the
// exact logical size of the physical test phone (Samsung Galaxy A17:
// 1080 x 2340 px @ 450 dpi => devicePixelRatio 2.8125, 384 x 832 dp).
//
// The isolated-widget tests that came first sized BrandLogoCircle explicitly
// (SizedBox(52)), which is why they passed while the phone showed overflowing
// wordmarks: in the real page the tile gives the coin tight 70 dp width
// constraints. Anything that needs to reason about the real layout must go
// through this harness.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:car_listing_app/features/home/home_flow.dart' show HomePage;
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:car_listing_app/theme_provider.dart' show AppThemes;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Samsung Galaxy A17 (SM-A175F).
const Size kA17PhysicalSize = Size(1080, 2340);
const double kA17DevicePixelRatio = 2.8125;

/// Logical size of the tile the Search picker gives each brand (see
/// `_searchBrandTileWidth` in home_search_filters_brand.dart).
const double kSearchTileWidth = 72;

final Map<String, ImageProvider> _logoMemo = {};

/// Resolves logos from the committed backend folder (identical bytes to the
/// bundled copies and to what the CDN serves), so the picker renders without
/// network access for bundled and non-bundled slugs alike.
void installLogoOverride() {
  debugBrandLogoImageOverride = (slug) {
    final f = File('kk/static/images/brands/$slug.png');
    // A brand without a file is a CDN 404 in production: undecodable bytes
    // make the real errorBuilder show the generic car icon, exactly like the
    // CachedNetworkImage errorWidget does on the phone.
    return _logoMemo.putIfAbsent(
      slug,
      () => MemoryImage(
        f.existsSync() ? f.readAsBytesSync() : Uint8List.fromList([0, 1, 2]),
      ),
    );
  };
}

void removeLogoOverride() => debugBrandLogoImageOverride = null;

/// Loads the real Roboto shipped with the Flutter SDK (the font the phone
/// uses) so label wrapping is measured with realistic glyph widths instead of
/// the test default "Ahem" (1 em wide squares). Returns false when unavailable.
Future<bool> loadRoboto(WidgetTester tester) async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (root != null) '$root/bin/cache/artifacts/material_fonts',
    r'C:\src\flutter\bin\cache\artifacts\material_fonts',
  ];
  for (final dir in candidates) {
    final regular = File('$dir/roboto-regular.ttf');
    if (!regular.existsSync()) continue;
    // One loader per file: a single FontLoader holding several weights of the
    // same family never completed under flutter_test here.
    for (final name in const [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]) {
      final f = File('$dir/$name');
      if (!f.existsSync()) continue;
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await tester.runAsync(
        () => loader.load().timeout(const Duration(seconds: 30)),
      );
    }
    final icons = File('$dir/materialicons-regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await tester.runAsync(
        () => loader.load().timeout(const Duration(seconds: 30)),
      );
    }
    return true;
  }
  return false;
}

Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Pumps the real Search Cars page on the A17 viewport with the full brand
/// grid expanded. [boundaryKey] wraps the page for screenshots.
Future<void> pumpSearchBrandPicker(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  bool light = true,
}) async {
  tester.view.physicalSize = kA17PhysicalSize;
  tester.view.devicePixelRatio = kA17DevicePixelRatio;
  addTearDown(tester.view.reset);
  installLogoOverride();
  addTearDown(removeLogoOverride);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: light ? AppThemes.lightTheme : AppThemes.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: boundaryKey,
        child: const HomePage.searchFilters(),
      ),
    ),
  );
  await settle(tester, frames: 20);

  final more = find.text('More');
  expect(more, findsOneWidget, reason: 'Search brand row must show "More"');
  await tester.ensureVisible(more);
  await tester.tap(more);
  await settle(tester);
}

/// Scrolls the expanded brand grid (the inner [GridView]) until a coin for
/// [brand] is built, then brings it on screen.
Future<Finder> revealBrand(WidgetTester tester, String brand) async {
  final coin = find.byWidgetPredicate(
    (w) => w is BrandLogoCircle && w.brand == brand,
  );
  final grid = find.byType(GridView).first;
  await rewindGrid(tester);
  for (var i = 0; i < 80 && coin.evaluate().isEmpty; i++) {
    await tester.drag(grid, const Offset(0, -140));
    await settle(tester, frames: 2);
  }
  final built = find
      .byType(BrandLogoCircle)
      .evaluate()
      .map((e) => (e.widget as BrandLogoCircle).brand)
      .toList();
  expect(
    coin,
    findsOneWidget,
    reason: 'brand "$brand" not found in grid; built now: $built',
  );
  await tester.ensureVisible(coin);
  await settle(tester, frames: 3);
  // Frame the grid nicely (below the pinned search bar) for screenshots.
  Scrollable.ensureVisible(
    tester.element(grid),
    alignment: 0.12,
    duration: const Duration(milliseconds: 1),
  );
  await settle(tester, frames: 3);
  return coin;
}

Future<void> rewindGrid(WidgetTester tester) async {
  final grid = find.byType(GridView).first;
  // The whole grid window must be on screen (not under the bottom action
  // bar) for drags aimed at its centre to hit it.
  await tester.ensureVisible(grid);
  await settle(tester, frames: 2);
  for (var i = 0; i < 4; i++) {
    await tester.fling(grid, const Offset(0, 3000), 8000);
    await settle(tester, frames: 4);
  }
}

/// Full-frame screenshot at the phone's real pixel size.
Future<Uint8List> shot(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: kA17DevicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  return bytes!;
}
