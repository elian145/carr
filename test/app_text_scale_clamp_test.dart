import 'package:car_listing_app/shared/ui/responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppResponsive.clampAppTextScaleFactor', () {
    test('ignores system font scale on regular phones', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(2.0, compactPhone: false),
        1.0,
      );
    });

    test('ignores system font scale on compact phones', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(2.0, compactPhone: true),
        1.0,
      );
    });

    test('stays at designed size for small or large system scale', () {
      expect(
        AppResponsive.clampAppTextScaleFactor(0.5, compactPhone: false),
        1.0,
      );
      expect(
        AppResponsive.clampAppTextScaleFactor(1.0, compactPhone: false),
        1.0,
      );
      expect(
        AppResponsive.clampAppTextScaleFactor(1.25, compactPhone: false),
        1.0,
      );
    });
  });
}
