import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/sell/sell_draft_archive.dart';

void main() {
  group('SellDraftArchive', () {
    test('normalizeSnapshot fills draftId and carData', () {
      final normalized = SellDraftArchive.normalizeSnapshot({
        'currentStep': 2,
        'carData': {'brand': 'Toyota'},
      });
      expect(normalized['draftId'], isNotEmpty);
      expect(normalized['carData'], {'brand': 'Toyota'});
      expect(normalized['currentStep'], 2);
    });

    test('isVisibleDraft requires meaningful carData', () {
      expect(
        SellDraftArchive.isVisibleDraft({'carData': {'brand': 'BMW'}}),
        isTrue,
      );
      expect(
        SellDraftArchive.isVisibleDraft({'carData': {}}),
        isFalse,
      );
    });

    test('encode and decode archive round-trip', () {
      final drafts = [
        SellDraftArchive.normalizeSnapshot({
          'carData': {'brand': 'Audi'},
        }),
      ];
      final decoded = SellDraftArchive.decodeArchive(
        SellDraftArchive.encodeArchive(drafts),
      );
      expect(decoded.length, 1);
      expect(decoded.first['carData'], {'brand': 'Audi'});
    });
  });
}
