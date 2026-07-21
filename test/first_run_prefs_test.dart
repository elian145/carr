import 'package:car_listing_app/services/first_run_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirstRunPrefs.resetForTests();
  });

  test('FirstRunPrefs marks onboarding complete (UX-04)', () async {
    expect(await FirstRunPrefs.isComplete(), isFalse);
    await FirstRunPrefs.markComplete();
    expect(await FirstRunPrefs.isComplete(), isTrue);
  });
}
