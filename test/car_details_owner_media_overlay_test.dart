// Widget-level (full app + FakeApiServer) tests for the optimistic-
// local-media fix's wiring into `car_details_page_media.dart`/
// `car_details_page_build_hero.dart`: `OwnerFallbackHeroImage`/
// `OwnerFallbackVideoThumbnail` get mounted (instead of the plain
// `ListingHeroImage`/`NetworkVideoThumbnailPreview`) for the owner's own
// in-flight submission items, and the "Processing media" badge follows
// the expected-vs-remote-display-ready completion rule -- see
// `owner_media_overlay.dart` and `car_details_page_media.dart`'s
// `_showProcessingMedia` doc comment.
//
// Uses `debugOwnerFallbackHeroRemoteProbeOverride`/
// `debugOwnerFallbackVideoRemoteProbeOverride` (the SAME test-only seams
// `owner_fallback_hero_image_test.dart`/`owner_fallback_video_thumbnail_
// test.dart` use) so the "remote confirmed displayable" transition is
// deterministic even inside the full app tree, without a real network
// image decode.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/app/widgets/owner_fallback_hero_image.dart';
import 'package:car_listing_app/app/widgets/owner_fallback_video_thumbnail.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:car_listing_app/shared/ui/processing_media_badge.dart';

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

/// Swipes the hero PageView through every page it is willing to report,
/// collecting the (localUrl, remoteUrl) pair for every distinct
/// `OwnerFallbackHeroImage` mounted along the way -- `PageView.builder`
/// only ever mounts a small window of pages at once, so a single
/// `find.byType` snapshot cannot see all N owner-fallback tiles at once.
/// Same technique as `listing_details_five_image_gallery_test.dart`'s
/// `swipeThroughHeroGallery`.
Future<List<({String localUrl, String? remoteUrl})>>
    _swipeThroughOwnerFallbackHeroTiles(
  WidgetTester tester, {
  required int maxPages,
}) async {
  final seen = <({String localUrl, String? remoteUrl})>[];
  for (var i = 0; i < maxPages; i++) {
    final widgets = tester
        .widgetList<OwnerFallbackHeroImage>(
          find.byType(OwnerFallbackHeroImage),
        )
        .toList();
    for (final w in widgets) {
      final pair = (localUrl: w.localUrl, remoteUrl: w.remoteUrl);
      if (!seen.any(
        (s) => s.localUrl == pair.localUrl && s.remoteUrl == pair.remoteUrl,
      )) {
        seen.add(pair);
      }
    }
    final pageView = find.byType(PageView);
    if (pageView.evaluate().isEmpty) break;
    await tester.drag(pageView, const Offset(-600, 0));
    for (var settle = 0; settle < 8; settle++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return seen;
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
    debugOwnerFallbackHeroRemoteProbeOverride = null;
    debugOwnerFallbackVideoRemoteProbeOverride = null;
  });

  tearDown(() async {
    await ApiService.clearTokens();
    AuthService().resetTestSession();
    FakeApiServer.carDetailOverrides.clear();
    debugOwnerFallbackHeroRemoteProbeOverride = null;
    debugOwnerFallbackVideoRemoteProbeOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'Scenario A: 5 local photos, server has none -- gallery shows all 5 '
    'via OwnerFallbackHeroImage (local, remoteUrl null), and the '
    '"Processing media" badge is visible',
    (tester) async {
      const carId = 'overlay_scn_a';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_overlay_a',
        carId: carId,
        images: List.generate(5, (i) => {'source': '/tmp/p$i.jpg'}),
      );

      await _openCarDetailAndSettle(tester, carId);

      final tiles = await _swipeThroughOwnerFallbackHeroTiles(
        tester,
        maxPages: 6,
      );
      expect(tiles, hasLength(5));
      for (final t in tiles) {
        expect(t.remoteUrl, isNull);
        expect(t.localUrl.startsWith('/tmp/p'), isTrue);
      }
      expect(find.byType(ProcessingMediaBadge), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Scenario C->D: remote confirmed displayable for one slot -- badge '
    'stays visible (other slots still local) until every slot has been '
    'confirmed',
    (tester) async {
      const carId = 'overlay_scn_cd';
      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(200, {
            'car': _ownedCar(
              carId,
              images: [
                {
                  'id': 1,
                  'image_url': 'https://cdn.example.com/p0_server.jpg',
                  'kind': 'listing',
                },
              ],
            ),
          });
      await _seedPendingRecord(
        draftId: 'draft_overlay_cd',
        carId: carId,
        images: [
          {'source': '/tmp/p0.jpg'},
          {'source': '/tmp/p1.jpg'},
        ],
      );
      // Deterministically confirm remote display-ready for whichever
      // slot gets a remoteUrl (only the first, per the positional-pairing
      // contract) -- never for a slot with no remoteUrl.
      debugOwnerFallbackHeroRemoteProbeOverride = (url) async => true;

      await _openCarDetailAndSettle(tester, carId);
      // Let the async remote-probe callbacks resolve and rebuild.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tiles = await _swipeThroughOwnerFallbackHeroTiles(
        tester,
        maxPages: 4,
      );
      expect(tiles, hasLength(2));
      expect(
        tiles.where((t) => t.remoteUrl != null),
        hasLength(1),
        reason: 'only the first slot has a remote counterpart yet',
      );
      expect(
        find.byType(ProcessingMediaBadge),
        findsOneWidget,
        reason: 'the 2nd slot is still local-only -- badge must stay up',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'Scenario I: server has fully caught up (durable record removed) -- '
    'no owner-fallback widgets, no "Processing media" badge',
    (tester) async {
      const carId = 'overlay_scn_i';
      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(200, {
            'car': _ownedCar(
              carId,
              images: [
                {
                  'id': 1,
                  'image_url': 'https://cdn.example.com/p0_server.jpg',
                  'kind': 'listing',
                },
              ],
            ),
          });
      // No durable record at all -- media pipeline already finished and
      // removed it (the real completion path).

      await _openCarDetailAndSettle(tester, carId);

      expect(find.byType(OwnerFallbackHeroImage), findsNothing);
      expect(find.byType(ProcessingMediaBadge), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'video slot: OwnerFallbackVideoThumbnail is mounted (not the plain '
    'NetworkVideoThumbnailPreview) for the owner\'s own pending video',
    (tester) async {
      const carId = 'overlay_scn_video';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_overlay_video',
        carId: carId,
        videos: [
          {'source': '/tmp/clip.mp4'},
        ],
      );

      await _openCarDetailAndSettle(tester, carId);

      final videoFallbacks = tester
          .widgetList<OwnerFallbackVideoThumbnail>(
            find.byType(OwnerFallbackVideoThumbnail),
          )
          .toList();
      expect(videoFallbacks, hasLength(1));
      expect(videoFallbacks.single.localUrl, '/tmp/clip.mp4');
      expect(videoFallbacks.single.remoteUrl, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'a non-owner never sees OwnerFallbackHeroImage/the processing badge, '
    'even though a durable record exists for this carId on this device',
    (tester) async {
      const carId = 'overlay_scn_nonowner';
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _ownedCar(carId)});
      await _seedPendingRecord(
        draftId: 'draft_overlay_nonowner',
        carId: carId,
        images: [
          {'source': '/tmp/p0.jpg'},
        ],
      );
      await AuthService().adoptTestSession(
        user: {'id': 'someone_else', 'username': 'buyer'},
      );

      await _openCarDetailAndSettle(tester, carId);

      expect(find.byType(OwnerFallbackHeroImage), findsNothing);
      expect(find.byType(ProcessingMediaBadge), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
