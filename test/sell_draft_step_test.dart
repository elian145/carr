import 'package:car_listing_app/shared/prefs/sell_draft_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readSellDraftStepDynamic', () {
    test('returns 0 for null and empty', () {
      expect(readSellDraftStepDynamic(null), 0);
      expect(readSellDraftStepDynamic(''), 0);
      expect(readSellDraftStepDynamic('   '), 0);
    });

    test('parses int, double, and string forms', () {
      expect(readSellDraftStepDynamic(2), 2);
      expect(readSellDraftStepDynamic(2.7), 3);
      expect(readSellDraftStepDynamic('1.0'), 1);
      expect(readSellDraftStepDynamic('4'), 4);
    });

    test('clamps to maxIdx', () {
      expect(readSellDraftStepDynamic(99, maxIdx: 4), 4);
      expect(readSellDraftStepDynamic(-3, maxIdx: 4), 0);
    });
  });

  group('mergeSellDraftStep', () {
    test('prefers higher step', () {
      expect(mergeSellDraftStep(jsonStep: 1, prefsStep: 3), 3);
      expect(mergeSellDraftStep(jsonStep: 4, prefsStep: 2), 4);
    });

    test('uses json when prefs missing', () {
      expect(mergeSellDraftStep(jsonStep: 2), 2);
    });
  });

  group('maxSellDraftStep', () {
    test('returns highest clamped value', () {
      expect(maxSellDraftStep(1, 3, 2), 3);
      expect(maxSellDraftStep(9, 1, 0), 4);
    });
  });
}
