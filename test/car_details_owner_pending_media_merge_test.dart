// Widget-level regression test for task item #14 ("listing detail behavior
// for owner"): the owner's Car Details page must merge this device's own
// still-in-flight local Sell-submission media into a freshly-loaded
// listing, and NEVER run a genuine local file path through
// `buildLegacyFullImageUrl` (which would otherwise mangle it into a
// broken URL) -- see `owner_pending_media_merge.dart` and the fix in
// `car_details_page_media.dart`'s `_heroImageEntries`/`_videoUrls`.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/app/widgets/listing_hero_image.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:car_listing_app/widgets/network_video_thumbnail.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _ownedCar(
  String id, {
  List<dynamic> images = const [],
  List<dynamic> videos = const [],
}) => {
      'id': id,
      'public_id': id,
      'title': 'Test car',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': '',
      'images': images,
      'videos': videos,
      'seller': {'id': 'seller_owner_1', 'username': 'seller'},
    };

Future<void> _seedPendingRecord({
  required String draftId,
  required String carId,
  List<dynamic> images = const [],
  List<dynamic> videos = const [],
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await SellSubmissionStatePrefs.upsert(
    SellSubmissionRecord(
      draftId: draftId,
      status: SellSubmissionStatus.inProgress,
      carId: carId,
      carData: {'images': images, 'videos': videos},
      idempotencyKey: 'sell-create-$draftId',
      createdAt: now,
      updatedAt: now,
      ownerUserId: 'seller_owner_1',
    ),
  );
}

Future<void> _openCarDetailAndSettle(WidgetTester tester, String carId) async {
  await tester.pumpWidget(const legacy.MyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/car_detail', arguments: {'carId': carId});
  await tester.pump();

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.textContaining('Camry').evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeApiServer.ensureStarted();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'push_enabled': false});
    await AuthService().adoptTestSession(
      user: {
        'id': 'seller_owner_1',
        'username': 'seller',
        'is_admin': false,
        'account_type': 'individual',
      },
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.carDetailOverrides.clear();
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'owner sees a pending local image (exact raw local path, never run '
    'through buildLegacyFullImageUrl) before it is remotely attached',
    (tester) async {
      const carId = 'owner_merge_img_1';
      const localPath = '/tmp/owner_pending_photo.jpg';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_owner_img_1',
        carId: carId,
        images: [
          {'source': localPath},
        ],
      );

      await _openCarDetailAndSettle(tester, carId);

      final heroImages = tester
          .widgetList<ListingHeroImage>(find.byType(ListingHeroImage))
          .toList();
      expect(
        heroImages.any((w) => w.url == localPath),
        isTrue,
        reason: 'the exact local path must reach ListingHeroImage unchanged '
            '-- found urls: ${heroImages.map((w) => w.url).toList()}',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'owner sees a pending local (normal) video and it plays from its exact '
    'localSourcePath -- never mangled into a broken static-uploads URL',
    (tester) async {
      const carId = 'owner_merge_vid_1';
      const localPath = '/tmp/owner_pending_video.mp4';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_owner_vid_1',
        carId: carId,
        videos: [
          {'source': localPath},
        ],
      );

      await _openCarDetailAndSettle(tester, carId);

      final thumbs = tester
          .widgetList<NetworkVideoThumbnailPreview>(
            find.byType(NetworkVideoThumbnailPreview),
          )
          .toList();
      expect(
        thumbs.any((w) => w.videoUrl == localPath),
        isTrue,
        reason: 'the exact local path must reach the video preview '
            'unchanged -- found urls: '
            '${thumbs.map((w) => w.videoUrl).toList()}',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a non-owner viewing the SAME carId never sees the local pending media '
    '-- ownership gate stays effective even though a durable record for '
    'this carId exists on the device',
    (tester) async {
      const carId = 'owner_merge_nonowner_1';
      const localPath = '/tmp/owner_pending_photo_2.jpg';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_owner_nonowner_1',
        carId: carId,
        images: [
          {'source': localPath},
        ],
      );
      // Sign in as a DIFFERENT account than the one that owns the
      // durable record / listing.
      await AuthService().adoptTestSession(
        user: {'id': 'someone_else', 'username': 'buyer'},
      );

      await _openCarDetailAndSettle(tester, carId);

      final heroImages = tester
          .widgetList<ListingHeroImage>(find.byType(ListingHeroImage))
          .toList();
      expect(
        heroImages.any((w) => w.url == localPath),
        isFalse,
        reason: 'a non-owner must never see this device\'s local pending '
            'media, even though a durable record exists for this carId',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
