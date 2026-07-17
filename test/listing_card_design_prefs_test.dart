import 'package:car_listing_app/app/widgets/global_listing_card.dart';
import 'package:car_listing_app/shared/prefs/listing_layout_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both listing card families expose twenty explicit presets', () {
    expect(horizontalListingCardPresetCount, 20);
    expect(gridListingCardPresetCount, 20);
  });

  test('card design values are sanitized to the supported range', () {
    expect(ListingLayoutPrefs.sanitizeCardDesign(1), 1);
    expect(ListingLayoutPrefs.sanitizeCardDesign('20'), 20);
    expect(ListingLayoutPrefs.sanitizeCardDesign(0), 1);
    expect(ListingLayoutPrefs.sanitizeCardDesign(21), 1);
    expect(ListingLayoutPrefs.sanitizeCardDesign('invalid'), 1);
  });

  test('load restores horizontal and grid designs independently', () async {
    SharedPreferences.setMockInitialValues({
      'listing_columns_v1': 2,
      'listing_horizontal_card_design_v1': 7,
      'listing_grid_card_design_v1': 16,
    });

    await ListingLayoutPrefs.load();

    expect(ListingLayoutPrefs.horizontalCardDesign.value, 7);
    expect(ListingLayoutPrefs.gridCardDesign.value, 16);
  });

  test('setters persist sanitized designs independently', () async {
    SharedPreferences.setMockInitialValues({});

    await ListingLayoutPrefs.setHorizontalCardDesign(12);
    await ListingLayoutPrefs.setGridCardDesign(99);
    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getInt('listing_horizontal_card_design_v1'), 12);
    expect(preferences.getInt('listing_grid_card_design_v1'), 1);
  });
}
