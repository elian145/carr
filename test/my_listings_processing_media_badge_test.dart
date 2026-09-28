// Widget-level regression test for task item #12/#13 ("My Listings shows
// the new listing immediately" + "optional subtle Processing media
// indicator, no blocking spinner"): a listing backed by a durable
// `SellSubmissionRecord` on this device shows the "Processing media"
// badge; a listing with no such record does not -- see
// `OwnerPendingMediaMerge.processingCarIds`/`isMediaProcessing` and
// `MyListingsPage._applyOwnerPendingMediaMerge`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';

import 'fake_api_server.dart';

Map<String, dynamic> _car(String id, {required String status}) => {
      'id': id,
      'public_id': id,
      'title': 'Test car $id',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': <dynamic>[],
      'videos': <dynamic>[],
      'status': status,
      'seller': {'id': 'seller_1', 'username': 'seller'},
    };

Future<void> _seedPendingRecord(String draftId, String carId) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await SellSubmissionStatePrefs.upsert(
    SellSubmissionRecord(
      draftId: draftId,
      status: SellSubmissionStatus.inProgress,
      carId: carId,
      carData: const {
        'images': <dynamic>[],
        'videos': <dynamic>[
          {'source': '/tmp/still_uploading.mp4'},
        ],
      },
      idempotencyKey: 'sell-create-$draftId',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await ApiService.clearTokens();
    await AuthService().adoptTestSession(
      user: {
        'id': 1,
        'username': 'seller',
        'is_admin': false,
        'is_verified': true,
        'account_type': 'individual',
      },
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.myListingsByStatus = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> openMyListings(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/my_listings');
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Active').evaluate().isNotEmpty) break;
    }
    // Extra settle time for the async `_applyOwnerPendingMediaMerge` pass
    // (a second, deliberately-async merge step run right after the
    // initial fetch's setState -- see `MyListingsPage._fetch`).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'a listing with a durable pending-submission record on this device '
    'shows the "Processing media" badge; an unrelated listing with no '
    'such record does not',
    (tester) async {
      FakeApiServer.myListingsByStatus = {
        '': [
          _car('processing_1', status: 'active'),
          _car('done_1', status: 'active'),
        ],
      };
      await _seedPendingRecord('draft_processing_1', 'processing_1');

      await openMyListings(tester);

      expect(find.text('Processing media'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'no durable records anywhere -- no "Processing media" badge is shown '
    'for any listing',
    (tester) async {
      FakeApiServer.myListingsByStatus = {
        '': [_car('plain_1', status: 'active')],
      };

      await openMyListings(tester);

      expect(find.text('Processing media'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
