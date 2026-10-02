// Bug B regression tests ("Listing Details does not show all media
// immediately"): real-device report that right after submitting a new
// listing with 5 photos + 1 video, Listing Details only showed the video
// plus the "Processing media" badge -- the other photos only appeared one
// at a time after repeatedly leaving and re-entering the page, never on
// their own.
//
// Root cause #1 (stable slot count): `PendingSellSubmissionService
// ._runSubmission`'s success path removes the `SellSubmissionRecord`
// (`SellSubmissionStatePrefs.remove`) BEFORE Car Details is ever opened,
// so `OwnerPendingMediaMerge.mergeIfOwner` -- which only ever appends
// local fallback images while THAT record still exists -- contributes
// nothing. The only remaining source of truth is the durable
// `OwnerOptimisticMediaRecord` (`owner_optimistic_media_prefs.dart`), but
// `OwnerMediaOverlay`'s slots built from it were previously used only to
// TAG existing gallery entries, never to INSERT a slot for an item the
// base list was missing entirely -- so any expected item with neither a
// local-only nor a remote-only row already present in the base list
// (e.g. every item, right after creation) silently had no gallery tile at
// all. Fixed in `car_details_page_media.dart`'s
// `_applyOwnerImageFallbackOverlay`/`_heroVideoEntries` -- see their
// "Stable-slots fix" doc comments.
//
// Root cause #2 (no auto-reconciliation): nothing in Car Details ever
// re-fetched the listing while owner media was still processing -- the
// owner had to manually leave and re-enter the page to see server
// progress. Fixed via `_CarDetailsPageLoad._maybeScheduleOwnerMediaPoll`
// (a periodic re-fetch while `_showProcessingMedia` is true, with
// dispose/background/foreground lifecycle handling).
//
// These tests seed an `OwnerOptimisticMediaRecord` DIRECTLY (never a
// `SellSubmissionStatePrefs` record) to reproduce the exact broken
// lifecycle: by the time Car Details opens, the submission record is
// already gone and only the optimistic record remains -- precisely
// `OwnerMediaOverlay.buildFromOptimisticRecordForCarId`'s path.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:car_listing_app/app/production_app.dart' as legacy;
import 'package:car_listing_app/pages/car_details_page.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/auth_service.dart';
import 'package:car_listing_app/shared/ui/processing_media_badge.dart';
import 'package:car_listing_app/shared/prefs/owner_optimistic_media_prefs.dart';

import 'fake_api_server.dart';

http.Response _jsonResponse(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _carWithMedia(
  String id, {
  List<dynamic> images = const [],
  List<dynamic> videos = const [],
}) =>
    {
      'id': id,
      'public_id': id,
      'title': 'Six Media Car',
      'brand': 'toyota',
      'model': 'camry',
      'year': 2020,
      'price': 10000,
      'currency': 'USD',
      'location': 'Erbil',
      'image_url': images.isNotEmpty ? images.first['image_url'] : '',
      'images': images,
      'videos': videos,
      'seller': {'id': 'seller_owner_1', 'username': 'seller'},
    };

Future<void> _seedOptimisticRecord({
  required String carId,
  required int imageCount,
  required int videoCount,
}) async {
  final items = <OwnerOptimisticMediaItem>[
    for (var i = 0; i < imageCount; i++)
      OwnerOptimisticMediaItem(
        clientMediaId: 'img_$i',
        kind: 'image',
        order: i,
        localPath: '/tmp/stable_slot_photo_$i.jpg',
      ),
    for (var i = 0; i < videoCount; i++)
      OwnerOptimisticMediaItem(
        clientMediaId: 'vid_$i',
        kind: 'video',
        order: i,
        localPath: '/tmp/stable_slot_video_$i.mp4',
      ),
  ];
  await OwnerOptimisticMediaPrefs.upsert(
    OwnerOptimisticMediaRecord(
      listingId: carId,
      items: items,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
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

int _heroPageViewItemCount(WidgetTester tester) {
  final pageView = tester.widget<PageView>(find.byType(PageView).first);
  final delegate = pageView.childrenDelegate as SliverChildBuilderDelegate;
  return delegate.childCount ?? -1;
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
    debugCarDetailsBackgroundImageProbeOverride = null;
    debugCarDetailsBackgroundVideoProbeOverride = null;
  });

  tearDownAll(() async {
    await FakeApiServer.stop();
  });

  testWidgets(
    'E: 5 photos + 1 video, backend initially returns 0 media -- Listing '
    'Details renders 6 local slots immediately (not 0, not growing from '
    '1/6)',
    (tester) async {
      const carId = 'stable_slots_car_1';
      await _seedOptimisticRecord(carId: carId, imageCount: 5, videoCount: 1);
      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(
            200,
            {'car': _carWithMedia(carId)},
          );

      await _openCarDetailAndSettle(tester, carId);

      expect(
        _heroPageViewItemCount(tester),
        6,
        reason: 'all 5 expected local photos + 1 expected local video must '
            'already be represented as gallery slots on the very first '
            'frame, using local sources, with zero media returned by the '
            'backend so far',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'F/G: backend progresses 0 -> 2 -> 6 across automatic reconciliation '
    'ticks, with NO manual refresh/reopen -- gallery stays exactly 6 '
    'slots throughout, never 1 -> 3 -> 5 -> 6',
    (tester) async {
      const carId = 'stable_slots_car_2';
      await _seedOptimisticRecord(carId: carId, imageCount: 5, videoCount: 1);

      var serverImageCount = 0;
      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(
            200,
            {
              'car': _carWithMedia(
                carId,
                images: List.generate(
                  serverImageCount,
                  (i) => {
                    'id': i + 1,
                    'image_url': 'https://cdn.example.com/stable_$i.jpg',
                    'is_primary': i == 0,
                    'order': i,
                    'kind': 'listing',
                  },
                ),
              ),
            },
          );

      await _openCarDetailAndSettle(tester, carId);
      expect(_heroPageViewItemCount(tester), 6, reason: 'initial frame');

      // Backend now has 2 of the 5 images attached. The owner-media poll
      // timer (~2s interval) must pick this up WITHOUT any manual
      // refresh/navigation.
      serverImageCount = 2;
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _heroPageViewItemCount(tester),
        6,
        reason: 'gallery must still have exactly 6 slots once the backend '
            'has attached 2 of 5 images -- those 2 begin remote '
            'reconciliation, the remaining 3 photos + 1 video stay local, '
            'the count itself must never change',
      );

      // Backend now has all 5 images attached.
      serverImageCount = 5;
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _heroPageViewItemCount(tester),
        6,
        reason: 'gallery must still have exactly 6 slots once the backend '
            'has attached all 5 images (only the video remains local) -- '
            'the source changes, not the slot count',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'K: disposing Listing Details (navigating away) stops the owner-media '
    'poll timer',
    (tester) async {
      const carId = 'stable_slots_car_3';
      await _seedOptimisticRecord(carId: carId, imageCount: 1, videoCount: 0);
      FakeApiServer.carDetailOverrides[carId] =
          () => _jsonResponse(200, {'car': _carWithMedia(carId)});

      await _openCarDetailAndSettle(tester, carId);

      final pageFinder = find.byType(CarDetailsPage);
      expect(pageFinder, findsOneWidget);
      // ignore: avoid_dynamic_calls
      final dynamic state = tester.state(pageFinder);
      // ignore: avoid_dynamic_calls
      final Timer? timer = state.debugOwnerMediaPollTimer;
      expect(
        timer,
        isNotNull,
        reason: 'the poll timer must be scheduled while owner media is '
            'still processing',
      );
      expect(timer!.isActive, isTrue);

      // Navigate back, disposing the Car Details page. Give the route's
      // exit transition time to finish so the old page is actually
      // disposed (not just visually covered) -- same pattern as
      // `f06_car_detail_cancellation_test.dart`.
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        timer.isActive,
        isFalse,
        reason: 'dispose() must cancel the owner-media poll timer, exactly '
            'like it already cancels the in-flight car-detail load token '
            '(F-06)',
      );
      // ignore: avoid_dynamic_calls
      expect(
        state.debugOwnerMediaPollTimer,
        isNull,
        reason: 'the field itself must also be cleared, not just the '
            'underlying Timer cancelled, so a later re-schedule check '
            "(`_ownerMediaPollTimer != null`) can't mistake a disposed "
            "page's stale timer for one still in use",
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'L (real-device acceptance fix): "Processing media" badge clears '
    'purely from background polling once the backend has attached '
    'every item -- WITHOUT the owner ever swiping to any off-screen '
    'hero slide (the PageView only ever builds the first slide)',
    (tester) async {
      const carId = 'stable_slots_car_4';
      await _seedOptimisticRecord(carId: carId, imageCount: 5, videoCount: 1);
      // Deterministic stand-ins for each fallback widget's own
      // `ImageStream`/`VideoThumbnail` probe -- see
      // `_backgroundProbeImageDecodes`/`_backgroundProbeVideoThumbnail`'s
      // own doc comments. Both report success unconditionally so this
      // test isolates exactly one thing: whether the page-level
      // background prober itself ever runs for a slide that was never
      // built, not whether a real image/video decode succeeds.
      debugCarDetailsBackgroundImageProbeOverride = (url) async => true;
      debugCarDetailsBackgroundVideoProbeOverride =
          (url) async => Uint8List.fromList(const [1, 2, 3]);

      FakeApiServer.carDetailOverrides[carId] = () => _jsonResponse(
            200,
            {
              'car': _carWithMedia(
                carId,
                images: List.generate(
                  5,
                  (i) => {
                    'id': i + 1,
                    'image_url': 'https://cdn.example.com/full_$i.jpg',
                    'is_primary': i == 0,
                    'order': i,
                    'kind': 'listing',
                    'client_media_id': 'img_$i',
                  },
                ),
                videos: [
                  {
                    'id': 1,
                    'video_url': 'https://cdn.example.com/full_vid.mp4',
                    'client_media_id': 'vid_0',
                  },
                ],
              ),
            },
          );

      await _openCarDetailAndSettle(tester, carId);
      // Sanity: the gallery already has all 6 slots on the first frame,
      // and only slide 0 (the hero's initial page) has ever been built
      // -- this test never calls any `PageController.animateToPage`/
      // drag gesture, so every OTHER slide's own
      // `OwnerFallbackHeroImage`/`OwnerFallbackVideoThumbnail` instance
      // is never constructed, and could never have run its own
      // `initState`-triggered probe.
      expect(_heroPageViewItemCount(tester), 6);
      expect(
        find.byType(ProcessingMediaBadge),
        findsOneWidget,
        reason: 'not yet reconciled on the very first frame',
      );

      // One owner-media poll tick: re-fetches (now fully server-attached)
      // media and runs the page-level background prober for every slot,
      // including the 5 that were never built.
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));

      // Let every background probe's future resolve and its own
      // `_markOwnerMediaRemoteDisplayReady` -> (serialized, per-listing-
      // locked) `OwnerOptimisticMediaCleanup.markRemoteDisplayReadyAndCleanup`
      // chain fully drain. That cleanup chain does a REAL `dart:io`
      // `File.exists()`/`delete()` -- a genuine OS-level async operation
      // that a plain `tester.pump()` loop never actually lets resolve
      // (confirmed directly: a bare `File(...).exists()` call issued
      // outside `runAsync` never completes across 20 `pump()`s in this
      // same Flutter SDK). `tester.runAsync()` is this repo's own
      // established fix for exactly this class of problem -- see
      // `sell_blur_preview_progressive_lifecycle_test.dart`'s `settle()`
      // (same "several real-event-loop runAsync rounds, not just one
      // pump()" reasoning: each resolved continuation is pinned to the
      // real zone it was issued from).
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(ProcessingMediaBadge).evaluate().isEmpty) break;
      }

      expect(
        find.byType(ProcessingMediaBadge),
        findsNothing,
        reason: 'every expected item has a confirmed-ready remote '
            'counterpart (per the background prober, not a widget '
            'build/swipe) and the durable record is gone -- the badge '
            'must clear itself without the owner swiping anywhere',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
