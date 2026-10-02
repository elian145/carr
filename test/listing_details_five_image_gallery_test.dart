// Real-device incident: seller reported only 1 of 5 uploaded photos
// visible on the final listing, even though production worker logs
// proved all 5 final Phase-A tasks self-attached successfully
// (skip_blur=True plate_blur_applied=False [BLUR TRACE SERVER] attached
// x5, five distinct client_media_ids).
//
// kk/tests/test_five_image_self_attach_serialization.py already proves
// the BACKEND is not the site of any 5-to-1 collapse: 5 self-attaches
// durably produce 5 CarImage rows, and GET /api/cars/<id> serializes all
// 5. This file answers the Flutter side: given the exact 5-image API
// shape the backend actually returns (images: [{id, image_url,
// is_primary, order, kind, ...}, ...] -- critically, WITHOUT any
// client_media_id/source_media_id field, since CarImage.source_media_id
// is deliberately never exposed in to_dict()/_with_media_compat()), does
// the real widget tree (API JSON -> _normalizeCarDetailMap ->
// OwnerPendingMediaMerge.mergeIfOwner -> _heroImageEntries -> the hero
// PageView.builder -> ListingHeroImage) actually render/expose all 5, or
// collapse them?
//
// The specific hypothesis under test (a dedupe/merge keyed by
// sourceMediaId ?? '', collapsing all-null-key server images to one) is
// proven NOT to happen below: server images never carry that field at
// all, and the merge only ever ADDS local fallback items on top of the
// server list (see owner_pending_media_merge.dart's _dedupeAppend, which
// returns base unchanged, or base + additions, but never fewer than
// base.length).
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

import 'fake_api_server.dart';

http.Response jsonResponse(int status, Object body) {
  return http.Response(
    json.encode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// The exact server shape _with_media_compat() (kk/routes/cars.py)
/// produces for n distinct, already-attached CarImage rows: full https
/// URLs (R2-configured production shape), kind "listing", exactly one
/// is_primary true, and deliberately no client_media_id/source_media_id
/// field anywhere.
List<Map<String, dynamic>> fiveServerImages() {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < 5; i++) {
    out.add({
      'id': i + 1,
      'image_url': 'https://cdn.example.com/car_photos/photo_$i.jpg',
      'is_primary': i == 0,
      'order': i,
      'kind': 'listing',
    });
  }
  return out;
}

Map<String, dynamic> carWithImages(String id, List<Map<String, dynamic>> images) {
  return {
    'id': id,
    'public_id': id,
    'title': 'Five Photo Car',
    'brand': 'toyota',
    'model': 'camry',
    'year': 2020,
    'price': 10000,
    'currency': 'USD',
    'location': 'Erbil',
    'image_url': images.isNotEmpty ? images.first['image_url'] : '',
    'images': images,
    'videos': <dynamic>[],
    'seller': {'id': 'seller_owner_1', 'username': 'seller'},
  };
}

Future<void> seedPendingRecord({
  required String draftId,
  required String carId,
  List<dynamic> images = const [],
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await SellSubmissionStatePrefs.upsert(
    SellSubmissionRecord(
      draftId: draftId,
      status: SellSubmissionStatus.inProgress,
      carId: carId,
      carData: {'images': images, 'videos': <dynamic>[]},
      idempotencyKey: 'sell-create-$draftId',
      createdAt: now,
      updatedAt: now,
      ownerUserId: 'seller_owner_1',
    ),
  );
}

Future<void> openCarDetailAndSettle(WidgetTester tester, String carId) async {
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

/// Swipes the hero PageView through every page it is willing to report,
/// collecting the ListingHeroImage.url visible at each stop. PageView
/// .builder only ever mounts a small window of pages at once, so this
/// (not a single find.byType snapshot) is the reliable way to prove how
/// many distinct images the gallery genuinely exposes for swiping -- the
/// real, user-visible behavior the seller described ("only one image
/// visible").
Future<List<String>> swipeThroughHeroGallery(
  WidgetTester tester, {
  required int maxPages,
}) async {
  final seen = <String>[];
  for (var i = 0; i < maxPages; i++) {
    final urls = tester
        .widgetList<ListingHeroImage>(find.byType(ListingHeroImage))
        .map((w) => w.url)
        .toList();
    for (final u in urls) {
      if (!seen.contains(u)) seen.add(u);
    }
    final pageView = find.byType(PageView);
    if (pageView.evaluate().isEmpty) break;
    await tester.drag(pageView, const Offset(-600, 0));
    for (var settle = 0; settle < 8; settle++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  // Final capture after the loop's last drag has fully settled.
  final urls = tester
      .widgetList<ListingHeroImage>(find.byType(ListingHeroImage))
      .map((w) => w.url)
      .toList();
  for (final u in urls) {
    if (!seen.contains(u)) seen.add(u);
  }
  return seen;
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

  group('Listing Details gallery must expose all 5 server images', () {
    testWidgets(
      'GET /api/cars/<id> returns 5 distinct images, no pending record -- '
      'the hero gallery must expose all 5 distinct URLs when swiped '
      'through, not collapse to 1',
      (tester) async {
        const carId = 'five_image_car_1';
        final images = fiveServerImages();
        FakeApiServer.carDetailOverrides[carId] =
            () => jsonResponse(200, {'car': carWithImages(carId, images)});

        await openCarDetailAndSettle(tester, carId);

        final seen = await swipeThroughHeroGallery(tester, maxPages: 6);
        expect(
          seen.toSet(),
          {
            'https://cdn.example.com/car_photos/photo_0.jpg',
            'https://cdn.example.com/car_photos/photo_1.jpg',
            'https://cdn.example.com/car_photos/photo_2.jpg',
            'https://cdn.example.com/car_photos/photo_3.jpg',
            'https://cdn.example.com/car_photos/photo_4.jpg',
          },
          reason: 'THE KEY ASSERTION: the gallery must expose all 5 '
              'distinct server image URLs when swiped through -- found: '
              '$seen',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group(
    'media-ready authority: server list must win, and a missing '
    'client_media_id/source_media_id must never collapse distinct server '
    'images',
    () {
      testWidgets(
        'media_status=ready equivalent: server already has 5 images, a '
        'STALE pending record on this device still lists only 1 local '
        'image (e.g. an old retry) -- the result must remain exactly the '
        '5 server images, never fewer',
        (tester) async {
          const carId = 'five_image_car_2';
          final images = fiveServerImages();
          FakeApiServer.carDetailOverrides[carId] =
              () => jsonResponse(200, {'car': carWithImages(carId, images)});
          // Stale durable record: still believes only 1 local image is
          // pending, even though the server has since attached all 5.
          await seedPendingRecord(
            draftId: 'draft_five_stale_1',
            carId: carId,
            images: [
              {'source': '/tmp/stale_pending_photo.jpg'},
            ],
          );

          await openCarDetailAndSettle(tester, carId);

          final seen = await swipeThroughHeroGallery(tester, maxPages: 6);
          expect(
            seen.where((u) => u.startsWith('https://cdn.example.com')).toSet(),
            {
              'https://cdn.example.com/car_photos/photo_0.jpg',
              'https://cdn.example.com/car_photos/photo_1.jpg',
              'https://cdn.example.com/car_photos/photo_2.jpg',
              'https://cdn.example.com/car_photos/photo_3.jpg',
              'https://cdn.example.com/car_photos/photo_4.jpg',
            },
            reason: 'server already covers this submissions only pending '
                'image (1 <= 5) -- no local fallback must be shown, and '
                'none of the 5 real server images may be dropped: '
                'found $seen',
          );
          expect(
            seen.contains('/tmp/stale_pending_photo.jpg'),
            isFalse,
            reason: 'the stale local fallback must not still be shown '
                'once the server already has more images than it',
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      testWidgets(
        '5 server images with no client_media_id/source_media_id field at '
        'all (the real production shape) must never collapse via any '
        'dedupe keyed on that field -- a Map keyed by sourceMediaId ?? '
        'empty-string would collapse all 5 onto a single key',
        (tester) async {
          const carId = 'five_image_car_3';
          final images = fiveServerImages();
          for (final img in images) {
            expect(
              img.containsKey('client_media_id'),
              isFalse,
              reason: 'sanity: this must match the real backend shape',
            );
            expect(img.containsKey('source_media_id'), isFalse);
          }
          FakeApiServer.carDetailOverrides[carId] =
              () => jsonResponse(200, {'car': carWithImages(carId, images)});

          await openCarDetailAndSettle(tester, carId);

          final seen = await swipeThroughHeroGallery(tester, maxPages: 6);
          expect(seen.length, 5);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    },
  );
}
