// F-10: unit tests for the text-scale policy in SystemDisplayLock.
import 'package:car_listing_app/shared/ui/app_text_scale.dart';
import 'package:car_listing_app/shared/ui/system_display_lock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android 14+ nonlinear font scaling: large text grows less than small text.
class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 12 ? fontSize * 2.0 : fontSize * 1.4;

  @override
  double get textScaleFactor => 1.4;
}

void main() {
  group('SystemDisplayLock.clampTextScale', () {
    test('bounds are 1.0 .. 2.0', () {
      expect(SystemDisplayLock.minTextScale, 1.0);
      expect(SystemDisplayLock.maxTextScale, 2.0);
    });

    test('values below 1 are raised to the designed size', () {
      expect(SystemDisplayLock.clampTextScale(0.85), 1.0);
      expect(SystemDisplayLock.clampTextScale(0.01), 1.0);
    });

    test('1.0, 1.3, 1.5 and 2.0 pass through unchanged', () {
      for (final v in const [1.0, 1.15, 1.3, 1.5, 1.99, 2.0]) {
        expect(SystemDisplayLock.clampTextScale(v), v, reason: '$v');
      }
    });

    test('absurd values are clamped to 2.0', () {
      expect(SystemDisplayLock.clampTextScale(2.01), 2.0);
      expect(SystemDisplayLock.clampTextScale(3.5), 2.0);
      expect(SystemDisplayLock.clampTextScale(1000), 2.0);
      expect(SystemDisplayLock.clampTextScale(double.maxFinite), 2.0);
    });

    test('non-finite or non-positive input falls back to 1.0', () {
      expect(SystemDisplayLock.clampTextScale(double.nan), 1.0);
      expect(SystemDisplayLock.clampTextScale(double.infinity), 1.0);
      expect(SystemDisplayLock.clampTextScale(double.negativeInfinity), 1.0);
      expect(SystemDisplayLock.clampTextScale(0), 1.0);
      expect(SystemDisplayLock.clampTextScale(-2), 1.0);
    });
  });

  group('SystemDisplayLock.lock text scaler', () {
    double scaledOf(double systemScale) {
      final locked = SystemDisplayLock.lock(
        MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(systemScale),
        ),
      );
      return locked.textScaler.scale(100) / 100;
    }

    test('0.8 -> 1.0, 1.0 -> 1.0, 1.5 -> 1.5, 2.0 -> 2.0, 4.0 -> 2.0', () {
      expect(scaledOf(0.8), closeTo(1.0, 1e-9));
      expect(scaledOf(1.0), closeTo(1.0, 1e-9));
      expect(scaledOf(1.5), closeTo(1.5, 1e-9));
      expect(scaledOf(2.0), closeTo(2.0, 1e-9));
      expect(scaledOf(4.0), closeTo(2.0, 1e-9));
    });

    test('result is a plain linear scaler (no nested-clamp assertion path)', () {
      final locked = SystemDisplayLock.lock(
        const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      );
      // Re-clamping an already locked scaler must not throw (see TS-01).
      expect(() => locked.textScaler.clamp(maxScaleFactor: 1.0), returnsNormally);
      expect(() => locked.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 2.0),
          returnsNormally);
    });

    test('nonlinear (Android 14) scalers are judged at body size, then clamped',
        () {
      // 14 sp body text -> 1.4x, not the 2.0x a 1 sp probe would report.
      expect(SystemDisplayLock.textScaleFactorOf(const _NonlinearScaler()),
          closeTo(1.4, 1e-9));
      final locked = SystemDisplayLock.lock(
        const MediaQueryData(textScaler: _NonlinearScaler()),
      );
      expect(locked.textScaler.scale(100) / 100, closeTo(1.4, 1e-9));
    });
  });

  testWidgets('appTextScaleOf reads the locked scale and never goes below 1.0',
      (tester) async {
    late double seen;
    Future<void> pumpAt(double scale) async {
      await tester.pumpWidget(
        MediaQuery(
          data: SystemDisplayLock.lock(
            MediaQueryData(textScaler: TextScaler.linear(scale)),
          ),
          child: Builder(
            builder: (context) {
              seen = appTextScaleOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    await pumpAt(0.7);
    expect(seen, 1.0);
    await pumpAt(1.5);
    expect(seen, closeTo(1.5, 1e-9));
    await pumpAt(9.0);
    expect(seen, closeTo(2.0, 1e-9));
  });
}
