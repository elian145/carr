import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/ui/app_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppHaptics helpers complete without throwing (L-02)', () async {
    await AppHaptics.selection();
    await AppHaptics.light();
    await AppHaptics.medium();
    await AppHaptics.heavy();
    await AppHaptics.success();
    await AppHaptics.warning();
  });
}
