import 'package:car_listing_app/features/listing/car_listing_specs_grid.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _car = <String, dynamic>{
  'mileage': 42355,
  'cylinders': 6,
  'engine_size': 3.5,
  'region_specs': 'us',
  'transmission': 'automatic',
  'fuel_type': 'gasoline',
  'trim': 'XLE',
  'condition': 'new',
  'drive_type': 'fwd',
  'body_type': 'sedan',
  'color': 'brown',
  'seating': 5,
};

const _designAspect = 1 / 1.05;

Widget _app({
  required double textScale,
  required double width,
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    builder: (context, appChild) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: appChild!,
      );
    },
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

SliverGridDelegateWithFixedCrossAxisCount _gridDelegate(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView).first);
  return grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
}

double _tileAspect(WidgetTester tester) {
  final delegate = _gridDelegate(tester);
  final gridW = tester.getSize(find.byType(GridView).first).width;
  final n = delegate.crossAxisCount;
  final tileW = (gridW - delegate.crossAxisSpacing * (n - 1)) / n;
  return delegate.mainAxisExtent! / tileW;
}

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double textScale,
  required double width,
}) {
  return tester.pumpWidget(
    _app(
      textScale: textScale,
      width: width,
      child: Builder(
        builder: (context) => buildCarListingSpecsGrid(context, _car),
      ),
    ),
  );
}

void main() {
  testWidgets('spec tiles stay 3-across at default scale with design aspect', (
    tester,
  ) async {
    await _pumpGrid(tester, textScale: 1.0, width: 358);
    await tester.pumpAndSettle();

    expect(_gridDelegate(tester).crossAxisCount, 3);
    expect(_tileAspect(tester), closeTo(_designAspect, 0.02));
    expect(find.text('Mileage'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large font and narrow width keep the original 3x2 layout', (
    tester,
  ) async {
    await _pumpGrid(tester, textScale: 1.0, width: 358);
    await tester.pumpAndSettle();
    final aspectAtDefault = _tileAspect(tester);

    await _pumpGrid(tester, textScale: 1.5, width: 280);
    await tester.pumpAndSettle();

    expect(_gridDelegate(tester).crossAxisCount, 3);
    expect(_tileAspect(tester), closeTo(aspectAtDefault, 0.02));
    expect(find.text('Mileage'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail rows keep designed size when text scale changes', (
    tester,
  ) async {
    await _pumpGrid(tester, textScale: 1.0, width: 358);
    await tester.pumpAndSettle();
    expect(find.text('Trim'), findsOneWidget);
    expect(find.text('XLE'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('XLE')).dx,
      greaterThan(200),
    );
    final iconAtDefault =
        tester.widget<Icon>(find.byIcon(Icons.layers).first).size!;

    await _pumpGrid(tester, textScale: 1.5, width: 358);
    await tester.pumpAndSettle();
    expect(find.text('Trim'), findsOneWidget);
    expect(find.text('XLE'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.layers).first).size!,
      closeTo(iconAtDefault, 0.1),
    );
    expect(tester.takeException(), isNull);
  });
}
