// Visual before/after contact sheet for the re-cut brand logos.
//
// Not a normal test: it only runs when BRAND_LOGO_SHEET_DIR is set, e.g.
//
//   $env:BRAND_LOGO_SHEET_DIR = 'D:\out'
//   $env:BRAND_LOGO_BEFORE_DIR = 'D:\before'   # old PNGs, <slug>.png
//   flutter test test/brand_logo_contact_sheet_test.dart
//
// It renders the REAL widgets (BrandLogoCircle / BrandLogoImage /
// FilterMakeSection) with the real bundled assets, next to a faithful copy of
// the OLD layout (unclipped Container + padding 8) drawn with the OLD files.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/ui/brand_logo_image.dart';
import 'package:car_listing_app/shared/ui/filter_make_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

const _affected = <String, String>{
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
const _reference = <String, String>{
  'Toyota': 'toyota',
  'BMW': 'bmw',
  'Mercedes-Benz': 'mercedes-benz',
};

String? _env(String k) {
  final v = Platform.environment[k];
  return (v == null || v.isEmpty) ? null : v;
}

final Map<String, ImageProvider> _memo = {};
ImageProvider _file(String path) =>
    _memo.putIfAbsent(path, () => MemoryImage(File(path).readAsBytesSync()));

class _OldCircle extends StatelessWidget {
  const _OldCircle(this.file, {this.selected = false});
  final File file;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    // Exact copy of the pre-fix tile in filter_make_section.dart.
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFFF6B00) : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(8),
        child: Image(image: _file(file.path), fit: BoxFit.contain),
      ),
    );
  }
}

class _NewCircle extends StatelessWidget {
  const _NewCircle(this.brand, {this.selected = false});
  final String brand;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFFF6B00) : const Color(0xFFE0E0E5),
          width: selected ? 2 : 1,
        ),
      ),
      child: BrandLogoCircle(brand: brand, size: 52, padding: 8),
    );
  }
}

Widget _chip({required Widget child}) => Container(
  width: 32,
  height: 32,
  padding: const EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFFD0D0D0)),
  ),
  child: child,
);

class _Checker extends StatelessWidget {
  const _Checker({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    height: 60,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _CheckerPainter()),
        child,
      ],
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const c = 6.0;
    final p1 = Paint()..color = const Color(0xFFD7D7D7);
    final p2 = Paint()..color = const Color(0xFFAAAAAA);
    for (var y = 0; y * c < size.height; y++) {
      for (var x = 0; x * c < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * c, y * c, c, c),
          (x + y).isEven ? p1 : p2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  final outDir = _env('BRAND_LOGO_SHEET_DIR');
  final beforeDir = _env('BRAND_LOGO_BEFORE_DIR');
  final bool skip = outDir == null || beforeDir == null;

  testWidgets('render before/after contact sheet', (tester) async {
    final out = Directory(outDir!)..createSync(recursive: true);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);

    // Real font for readable labels (Flutter tests default to boxy "Ahem").
    final arial = File(r'C:\Windows\Fonts\arial.ttf');
    var family = 'Roboto';
    if (arial.existsSync()) {
      final fl = FontLoader('SheetArial')
        ..addFont(Future.value(ByteData.sublistView(arial.readAsBytesSync())));
      await tester.runAsync(fl.load);
      family = 'SheetArial';
    }

    // Reference brands (network slugs) come from the repo's backend folder.
    debugBrandLogoImageOverride = (slug) {
      if (_reference.containsValue(slug)) {
        return _file('kk/static/images/brands/$slug.png');
      }
      return null; // bundled slugs use the REAL asset path
    };
    addTearDown(() => debugBrandLogoImageOverride = null);

    final all = <MapEntry<String, String>>[
      ..._affected.entries,
      ..._reference.entries,
    ];

    Widget label(
      String t, {
      Color? color,
      double size = 12,
      bool bold = false,
    }) => Text(
      t,
      style: TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color ?? Colors.black87,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    );

    Widget cell(Widget child, Color bg) => Container(
      width: 84,
      height: 72,
      color: bg,
      alignment: Alignment.center,
      child: child,
    );

    const light = Color(0xFFF2F2F5);
    const dark = Color(0xFF121212);

    Widget row(MapEntry<String, String> e, {required bool reference}) {
      final old = File('$beforeDir/${e.value}.png');
      return Row(
        children: [
          Container(
            width: 120,
            height: 72,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8),
            color: Colors.white,
            child: label(
              e.key + (reference ? '  (ref)' : ''),
              bold: !reference,
            ),
          ),
          cell(_OldCircle(old), light),
          cell(_NewCircle(e.key), light),
          cell(_OldCircle(old, selected: true), dark),
          cell(_NewCircle(e.key, selected: true), dark),
          cell(
            _chip(
              child: Image(image: _file(old.path), fit: BoxFit.contain),
            ),
            light,
          ),
          cell(_chip(child: BrandLogoImage(brand: e.key)), light),
          cell(
            _Checker(
              child: Image(image: _file(old.path), fit: BoxFit.contain),
            ),
            light,
          ),
          cell(
            _Checker(
              child: reference
                  ? Image(
                      image: _file('kk/static/images/brands/${e.value}.png'),
                      fit: BoxFit.contain,
                    )
                  : Image.asset(
                      brandLogoAssetPath(e.value),
                      fit: BoxFit.contain,
                    ),
            ),
            light,
          ),
        ],
      );
    }

    Widget header(String t, double w) => Container(
      width: w,
      height: 34,
      alignment: Alignment.center,
      color: const Color(0xFFDDDDE4),
      child: label(t, bold: true, size: 11),
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: Container(
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        header('Brand', 120),
                        header('BEFORE (light)', 84),
                        header('AFTER (light)', 84),
                        header('BEFORE (dark)', 84),
                        header('AFTER (dark)', 84),
                        header('BEFORE 32dp chip', 84),
                        header('AFTER 32dp chip', 84),
                        header('BEFORE raw file', 84),
                        header('AFTER raw file', 84),
                      ],
                    ),
                    for (final e in _affected.entries) row(e, reference: false),
                    Container(height: 6, width: 792, color: Colors.black54),
                    for (final e in _reference.entries) row(e, reference: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Decode all images before capturing.
    final ctx = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final e in all) {
        final providers = <ImageProvider>[
          _file('$beforeDir/${e.value}.png'),
          if (_reference.containsValue(e.value))
            _file('kk/static/images/brands/${e.value}.png')
          else
            AssetImage(brandLogoAssetPath(e.value)),
        ];
        for (final p in providers) {
          await precacheImage(p, ctx);
        }
      }
    });
    await tester.pump(const Duration(milliseconds: 200));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    for (final ratio in [4.0]) {
      await tester.runAsync(() async {
        final ui.Image img = await boundary.toImage(pixelRatio: ratio);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${out.path}/contact_sheet.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  }, skip: skip);

  // The real Sell / Filters brand picker (FilterMakeSection) with the grid
  // expanded, in light and dark themes, using the real bundled assets.
  testWidgets('render real FilterMakeSection grid (light + dark)', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(420, 1100);
    addTearDown(tester.view.reset);
    debugBrandLogoImageOverride = (slug) => _reference.containsValue(slug)
        ? _file('kk/static/images/brands/$slug.png')
        : null;
    addTearDown(() => debugBrandLogoImageOverride = null);

    final arial = File(r'C:\Windows\Fonts\arial.ttf');
    var family = 'Roboto';
    if (arial.existsSync()) {
      final fl = FontLoader('SheetArial2')
        ..addFont(Future.value(ByteData.sublistView(arial.readAsBytesSync())));
      await tester.runAsync(fl.load);
      family = 'SheetArial2';
    }
    ThemeData withFont(ThemeData t) =>
        t.copyWith(textTheme: t.textTheme.apply(fontFamily: family));

    final brands = [..._affected.keys, ..._reference.keys];
    final keys = [GlobalKey(), GlobalKey()];
    Widget themed(ThemeData theme, GlobalKey key) => Theme(
      data: theme,
      child: RepaintBoundary(
        key: key,
        child: Container(
          width: 420,
          height: 520,
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF121212)
              : const Color(0xFFF2F2F5),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamily: family),
            child: FilterMakeSection(
              brands: brands,
              selectedBrand: 'Vanderhall',
              onBrandSelected: (_) {},
              brandsExpanded: true,
              onToggleBrandsExpanded: () {},
              models: const {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                themed(withFont(ThemeData.light()), keys[0]),
                themed(withFont(ThemeData.dark()), keys[1]),
              ],
            ),
          ),
        ),
      ),
    );
    final ctx = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final e in _affected.entries) {
        await precacheImage(AssetImage(brandLogoAssetPath(e.value)), ctx);
      }
      for (final e in _reference.entries) {
        await precacheImage(
          _file('kk/static/images/brands/${e.value}.png'),
          ctx,
        );
      }
    });
    await tester.pump(const Duration(milliseconds: 200));
    final names = [
      'filter_make_section_light.png',
      'filter_make_section_dark.png',
    ];
    for (var i = 0; i < 2; i++) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(keys[i]),
      );
      await tester.runAsync(() async {
        final ui.Image img = await boundary.toImage(pixelRatio: 3);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${outDir!}/${names[i]}',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  }, skip: skip);
}
