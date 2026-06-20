import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/shared/prefs/sell_draft_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SellDraftPrefs listing draft', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('save, load, and clear round-trip per owner', () async {
      const owner = 'user_42';
      final draft = {'brand': 'Toyota', 'model': 'Camry', 'complete': false};

      await SellDraftPrefs.saveListingDraft(owner, draft);
      final loaded = await SellDraftPrefs.loadListingDraft(owner);

      expect(loaded, draft);

      await SellDraftPrefs.clearListingDraft(owner);
      expect(await SellDraftPrefs.loadListingDraft(owner), isNull);
    });

    test('load falls back to global key', () async {
      const owner = 'guest';
      final draft = {'brand': 'Honda'};

      final sp = await SharedPreferences.getInstance();
      await sp.setString('sell_listing_draft_v1_global', '{"brand":"Honda"}');

      expect(await SellDraftPrefs.loadListingDraft(owner), draft);
    });
  });
}
