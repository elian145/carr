// CarNet V1 feature-completeness batch 3 -- item 2 (video delete in
// Flutter edit flow).
//
// Bug: the sell wizard's edit flow never displayed already-uploaded
// listing videos at all -- `listingToSellDraftSnapshot()` reduced each
// server video (`{id, video_url, thumbnail_url}`) down to a bare URL
// string, and `_selectedVideos` (a `List<XFile>`) filtered out anything
// that wasn't a local file path via `ListingImageMedia.localFiles()`. So
// an owner had no way to see, let alone delete, a video that was already
// live on their listing.
//
// Fix: `listingToSellDraftSnapshot()` (lib/shared/listings/listing_to_sell_draft.dart)
// now also keeps the raw video records in `carData['existing_video_records']`.
// `_SellStep4Logic` (lib/features/sell/sell_step4_logic.dart) loads these
// into a new, separate `_existingServerVideos` list (kept apart from the
// new-video picker/upload pipeline) and renders them
// (lib/features/sell/sell_step4_build_videos.dart) with a delete button
// that calls `ApiService.deleteCarVideo()` (DELETE
// /api/cars/<car_id>/videos/<video_id>), removing the tile locally only
// once the backend call succeeds (rollback-by-inaction on failure).
//
// Release-candidate fix-up: the backend previously flattened `videos` to
// plain URL strings on every listing GET response path (see
// `kk/routes/cars.py::_serialize_videos`), so a real API response could
// never actually populate `existing_video_records`. Now fixed backend-side;
// this file's fixture builds a REAL backend-shaped `/api/cars/<id>` response
// (structured video objects) and runs it through the actual
// `listingToSellDraftSnapshot()` mapper below, instead of hand-crafting
// `existing_video_records` directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';

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
    FakeApiServer.deletedCarVideoCalls.clear();
    FakeApiServer.deleteCarVideoOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  Future<void> bootSellWizard(WidgetTester tester) async {
    await tester.pumpWidget(const legacy.MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Builds the edit-wizard `carData` the same way the real app does: starts
  /// from a REAL backend-shaped `/api/cars/<id>` listing response (structured
  /// `{id, video_url, thumbnail_url}` video objects -- the shape
  /// `kk/routes/cars.py::_serialize_videos` now returns) and runs it through
  /// the actual production mapper `listingToSellDraftSnapshot()`, instead of
  /// hand-crafting `existing_video_records` directly. This proves the fixed
  /// backend response shape flows correctly into the edit UI end-to-end.
  Map<String, dynamic> editDraftCarDataWithTwoExistingVideos() {
    final rawListingResponse = <String, dynamic>{
      // No `public_id` -- falls back to `id`, matching the delete-call
      // assertions below (`edit_car_1/601`).
      'id': 'edit_car_1',
      'brand': 'toyota',
      'model': 'camry',
      'trim': 'le',
      'year': 2020,
      'mileage': 50000,
      'condition': 'used',
      'transmission': 'auto',
      'fuel_type': 'gas',
      'body_type': 'sedan',
      'color': 'black',
      'seating': 5,
      'drive_type': 'fwd',
      'region_specs': 'gcc',
      'title_status': 'clean',
      'city': 'Erbil',
      'contact_phone': '7501234567',
      'image_url': '',
      // No local photos -- keeps `Icons.close` finder counts unambiguous
      // (photo tiles use the same remove icon as video tiles).
      'images': const <dynamic>[],
      'videos': const [
        {
          'id': 601,
          'video_url': 'https://cdn.example.com/car_videos/one.mp4',
          'thumbnail_url': 'https://cdn.example.com/car_videos/one.jpg',
        },
        {
          'id': 602,
          'video_url': 'https://cdn.example.com/car_videos/two.mp4',
          'thumbnail_url': 'https://cdn.example.com/car_videos/two.jpg',
        },
      ],
    };

    final snapshot = listingToSellDraftSnapshot(rawListingResponse);
    final carData = Map<String, dynamic>.from(
      snapshot['carData'] as Map<String, dynamic>,
    );
    // `sell_wizard_v2` is a wizard-entry flag unrelated to listing data;
    // `listingToSellDraftSnapshot()` doesn't set it, so add it here.
    carData['sell_wizard_v2'] = true;
    return carData;
  }

  testWidgets(
    'existing server videos are shown in the edit wizard with a delete '
    'button',
    (tester) async {
      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: editDraftCarDataWithTwoExistingVideos(),
      );

      expect(find.text('Already uploaded'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    },
  );

  testWidgets(
    'removing an existing video in edit mode deletes it on the backend and '
    'removes it from the grid',
    (tester) async {
      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: editDraftCarDataWithTwoExistingVideos(),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(FakeApiServer.deletedCarVideoCalls, ['edit_car_1/601']);
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );

  testWidgets(
    'a failed backend video delete keeps the video tile and surfaces an '
    'error instead of silently dropping it',
    (tester) async {
      FakeApiServer.deleteCarVideoOverride = (carId, videoId) {
        return http.Response(
          '{"message": "Failed to delete video."}',
          500,
          headers: {'content-type': 'application/json'},
        );
      };

      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: editDraftCarDataWithTwoExistingVideos(),
      );

      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The delete call was attempted, but rejected -- the video tile must
      // still be present (no client-side state loss on server rejection).
      expect(FakeApiServer.deletedCarVideoCalls, ['edit_car_1/601']);
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'a listing with no existing videos does not show the "already '
    'uploaded" section',
    (tester) async {
      await bootSellWizard(tester);
      await openSellDraftStep(
        tester,
        step: 0,
        carData: {
          ...editDraftCarDataWithTwoExistingVideos(),
          'existing_video_records': <dynamic>[],
        },
      );

      expect(find.text('Already uploaded'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    },
  );
}
