import 'package:car_listing_app/shared/ui/responsive.dart';
import 'package:car_listing_app/shared/ui/system_display_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the framework's real `SystemTextScaler` (returned by
/// `MediaQueryData.fromView` on real devices) for reproduction purposes: it
/// extends [TextScaler] and overrides only [scale]/[textScaleFactor],
/// deliberately leaving [TextScaler.clamp] as the inherited base
/// implementation. That base implementation (unlike `_LinearTextScaler`'s
/// own eager-resolving override) really does construct a `_ClampedTextScaler`
/// when `minScaleFactor != maxScaleFactor` -- which is the only way to
/// reproduce the nested-clamp assertion in a widget test, since
/// `SystemTextScaler` itself cannot be constructed outside the framework.
class _RealDeviceLikeTextScaler extends TextScaler {
  const _RealDeviceLikeTextScaler(this.textScaleFactor);

  @override
  final double textScaleFactor;

  @override
  double scale(double fontSize) => fontSize * textScaleFactor;
}

void main() {
  tearDown(() {
    SystemDisplayLock.debugStableDevicePixelRatio = null;
  });

  test('lock clamps system text scale to 1.3', () {
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(360, 800),
        devicePixelRatio: 2.625,
        textScaler: TextScaler.linear(1.8),
      ),
    );
    expect(locked.textScaler.scale(100), closeTo(130, 0.01));
    expect(locked.size, const Size(360, 800));
  });

  test('lock keeps text scale when already within range', () {
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(360, 800),
        textScaler: TextScaler.linear(1.15),
      ),
    );
    expect(locked.textScaler.scale(100), closeTo(115, 0.01));
  });

  test('lock restores bottom padding from viewPadding when keyboard is closed', () {
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(360, 800),
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 48),
      ),
    );
    expect(locked.padding.bottom, 48);
    expect(locked.viewPadding.bottom, 48);
  });

  test('lock does not force bottom padding while keyboard is open', () {
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(360, 800),
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 48),
        viewInsets: EdgeInsets.only(bottom: 300),
      ),
    );
    expect(locked.padding.bottom, 0);
  });

  test('lock restores designed logical size when display density grows', () {
    SystemDisplayLock.debugStableDevicePixelRatio = 3.0;
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(270, 600),
        devicePixelRatio: 4.0,
        textScaler: TextScaler.linear(2),
        padding: EdgeInsets.only(top: 18, bottom: 36),
        viewPadding: EdgeInsets.only(top: 18, bottom: 36),
      ),
    );
    expect(locked.textScaler.scale(100), closeTo(130, 0.01));
    expect(locked.devicePixelRatio, 3.0);
    expect(locked.size.width, closeTo(360, 0.01));
    expect(locked.size.height, closeTo(800, 0.01));
    expect(locked.padding.bottom, closeTo(48, 0.01));
    expect(SystemDisplayLock.visualScaleOf(
      const MediaQueryData(devicePixelRatio: 4.0),
    ), closeTo(0.75, 0.01));
  });

  testWidgets('wrapApp layouts at designed size then scales to the window', (
    tester,
  ) async {
    SystemDisplayLock.debugStableDevicePixelRatio = 3.0;
    late Size innerSize;
    late TextScaler innerScaler;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(270, 600),
          devicePixelRatio: 4.0,
          textScaler: TextScaler.linear(2),
        ),
        child: Builder(
          builder: (context) {
            return AppResponsive.wrapApp(
              context,
              Builder(
                builder: (context) {
                  innerSize = MediaQuery.sizeOf(context);
                  innerScaler = MediaQuery.textScalerOf(context);
                  return const SizedBox.expand();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(innerScaler.scale(100), closeTo(130, 0.01));
    expect(innerSize.width, closeTo(360, 0.5));
    expect(innerSize.height, closeTo(800, 0.5));
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets(
    'TS-01: BottomNavigationBar does not throw the _ClampedTextScaler '
    'assertion when the system text scale sits at the lock floor',
    (tester) async {
      // BottomNavigationBar internally re-clamps the inherited text scaler
      // to `maxScaleFactor: 1.0` for its labels (see
      // MediaQuery.withClampedTextScaling in bottom_navigation_bar.dart).
      // With a system textScaleFactor of exactly 1.0, SystemDisplayLock.lock
      // used to hand down a `_ClampedTextScaler` with min == max == 1.0,
      // and re-clamping that (max == min) previously hit an assertion
      // inside `_ClampedTextScaler.clamp()`. This must build cleanly.
      final locked = SystemDisplayLock.lock(
        const MediaQueryData(
          size: Size(360, 800),
          textScaler: _RealDeviceLikeTextScaler(1.0),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          // MaterialApp derives its own root MediaQuery from the platform
          // view, which would otherwise shadow an ancestor MediaQuery
          // wrapped around it -- `builder` is how app code actually injects
          // SystemDisplayLock's MediaQuery in production (see
          // lib/app/bootstrap.dart), so this must go through `builder` too
          // for BottomNavigationBar to see the locked textScaler.
          builder: (context, child) =>
              MediaQuery(data: locked, child: child!),
          home: Scaffold(
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: 0,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    },
  );
}
