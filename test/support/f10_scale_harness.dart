// Shared harness for the F-10 (system font scaling) widget tests.
//
// It mimics production: the window has the requested logical size and the
// requested system text scale is delivered through `MediaQuery` and then
// passed through the REAL `SystemDisplayLock.lock` (exactly what
// `AppResponsive.wrapApp` does in the shipped app), so the tests see the same
// text scaler the phone does, including the 1.0..2.0 clamp.
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/ui/system_display_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_picker_harness.dart' show loadRoboto;

/// Text scales every F-10 layout test runs at.
const List<double> kF10Scales = <double>[1.0, 1.5, 2.0];

/// Phone widths: regular and the narrowest supported (320 dp).
const double kF10RegularWidth = 360;
const double kF10NarrowWidth = 320;

/// Loads real Roboto so wrapping / overflow is judged with realistic glyph
/// widths instead of the 1-em-square "Ahem" test font. Returns false when the
/// SDK fonts cannot be found (tests then still run, with Ahem).
Future<bool> f10LoadFonts(WidgetTester tester) => loadRoboto(tester);

/// Sizes the test window to [width] x [height] logical px at DPR 1.0.
void f10SetWindow(
  WidgetTester tester, {
  double width = kF10RegularWidth,
  double height = 800,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Wraps [home] in a localized [MaterialApp] whose MediaQuery carries the
/// production-locked text scaler for [textScale].
Widget f10App({
  required Widget home,
  required double textScale,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? ThemeData(useMaterial3: false, fontFamily: 'Roboto'),
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      final raw = MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      );
      return MediaQuery(
        data: SystemDisplayLock.lock(raw),
        child: child!,
      );
    },
    home: home,
  );
}

/// Collects every framework exception thrown while pumping (RenderFlex
/// overflow is reported through FlutterError, which `takeException` returns).
Future<void> f10Pump(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 100));
}

/// True when [finder]'s widget is fully inside the (logical) window and has a
/// non-zero hit-testable size.
bool f10IsOnScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder.first);
  final win = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.width > 0 &&
      rect.height > 0 &&
      rect.left >= -0.5 &&
      rect.right <= win.width + 0.5 &&
      rect.top >= -0.5 &&
      rect.bottom <= win.height + 0.5;
}
