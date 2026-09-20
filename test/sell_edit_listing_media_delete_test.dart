// CarNet V1 feature-completeness batch 2 -- item 1 (edit listing: delete
// photos/videos from backend/storage), Flutter side.
//
// Bug: removing a photo from an existing listing in the sell wizard's edit
// mode only updated local widget state -- nothing ever told the backend to
// delete the corresponding `CarImage` row, so the "removed" photo stayed
// live on the server after saving.
//
// Fix: `_SellStep4Logic._removePhotoAt()` (lib/features/sell/sell_step4_logic.dart)
// now calls `ApiService.deleteCarImage()` (DELETE
// /api/cars/<car_id>/images/<image_id>) for any photo that already has a
// server-assigned id and we're editing an existing listing, and only removes
// it from local state once that call succeeds.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';

import 'fake_api_server.dart';
import 'legacy_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'push_enabled': false,
      'app_locale': 'en',
    });
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
    FakeApiServer.deletedCarImageCalls.clear();
    FakeApiServer.deleteCarImageOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> bootSellWizard(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Map<String, dynamic> editDraftCarDataWithTwoPhotos() => {
        'brand': 'toyota',
        'model': 'camry',
        'trim': 'le',
        'year': '2020',
        'mileage': '50000',
        'condition': 'used',
        'transmission': 'auto',
        'fuel_type': 'gas',
        'body_type': 'sedan',
        'color': 'black',
        'seating': '5',
        'drive_type': 'fwd',
        'region_specs': 'gcc',
        'title_status': 'clean',
        'city': 'Erbil',
        'contact_phone': '7501234567',
        'sell_wizard_v2': true,
        '_editListingId': 'edit_car_1',
        'images': <dynamic>[
          {
            'id': 501,
            'source': 'https://cdn.example.com/car_photos/one.jpg',
            'is_primary': true,
          },
          {
            'id': 502,
            'source': 'https://cdn.example.com/car_photos/two.jpg',
          },
        ],
      };

  testWidgets(
    'removing an existing photo in edit mode deletes it on the backend and '
    'removes it from the grid',
    (tester) async {
      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: editDraftCarDataWithTwoPhotos(),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(FakeApiServer.deletedCarImageCalls, ['edit_car_1/501']);
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );

  testWidgets(
    'a failed backend delete (e.g. last-photo invariant) keeps the photo in '
    'the grid and surfaces an error instead of silently dropping it',
    (tester) async {
      FakeApiServer.deleteCarImageOverride = (carId, imageId) {
        return http.Response(
          '{"message": "At least one photo is required."}',
          400,
          headers: {'content-type': 'application/json'},
        );
      };

      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: editDraftCarDataWithTwoPhotos(),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The delete call was attempted, but rejected -- the photo must still
      // be present (no client-side state loss on server rejection).
      expect(FakeApiServer.deletedCarImageCalls, ['edit_car_1/501']);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'removing a freshly-picked local photo (never uploaded, no server id) '
    'does not call the backend delete endpoint',
    (tester) async {
      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: {
          ...editDraftCarDataWithTwoPhotos(),
          // One persisted server photo (has an id) plus a locally-picked
          // file that was never uploaded (no id) -- removing the local
          // pick must be a pure client-side edit with no backend call.
          'images': <dynamic>[
            {
              'id': 501,
              'source': 'https://cdn.example.com/car_photos/one.jpg',
              'is_primary': true,
            },
            '/tmp/carnet_test_local_pick.jpg',
          ],
        },
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      // Remove the second tile (the local, never-uploaded pick).
      await tester.tap(find.byIcon(Icons.close).at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(FakeApiServer.deletedCarImageCalls, isEmpty);
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );
}
