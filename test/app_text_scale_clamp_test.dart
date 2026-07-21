import 'package:car_listing_app/shared/ui/responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppResponsive.clampAppTextScaleFactor (A-03)', () {
    test('caps extreme accessibility scale on regular phones', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(2.0, compactPhone: false),
        AppResponsive.maxAppTextScale,
      );
    });

    test('uses a tighter cap on compact phones', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(2.0, compactPhone: true),
        AppResponsive.maxAppTextScaleCompact,
      );
    });

    test('allows modest downscaling but not collapse', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(0.5, compactPhone: false),
        AppResponsive.minAppTextScale,
      );
      expect(
        AppResponsive.clampAppTextScaleFactor(1.0, compactPhone: false),
        1.0,
      );
      expect(
        AppResponsive.clampAppTextScaleFactor(1.25, compactPhone: false),
        1.25,
      );
    });
  });
}
