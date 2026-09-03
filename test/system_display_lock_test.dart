import 'package:car_listing_app/shared/ui/responsive.dart';
import 'package:car_listing_app/shared/ui/system_display_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    SystemDisplayLock.debugStableDevicePixelRatio = null;
  });

  test('lock ignores system text scale', () {
    final locked = SystemDisplayLock.lock(
      const MediaQueryData(
        size: Size(360, 800),
        devicePixelRatio: 2.625,
        textScaler: TextScaler.linear(1.8),
      ),
    );
    expect(locked.textScaler, TextScaler.noScaling);
    expect(locked.size, const Size(360, 800));
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
    expect(locked.textScaler, TextScaler.noScaling);
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

    expect(innerScaler, TextScaler.noScaling);
    expect(innerSize.width, closeTo(360, 0.5));
    expect(innerSize.height, closeTo(800, 0.5));
    expect(find.byType(FittedBox), findsOneWidget);
  });
}
