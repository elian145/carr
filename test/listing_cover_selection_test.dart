// Cover-photo selection -- client half of the contract.
//
// Real-device bug: the seller starred a photo that was NOT first, but the
// published listing still used another photo as its cover. The star was
// stored only in `carData['primary_image_index']`; nothing declared it to the
// server for a NEW listing, so the backend's self-attach made the cover
// whichever photo finished processing first.
//
// The cover and display order are now frozen into the `expected_media`
// manifest (`is_cover` / `sort_order`) that `create_car` registers. These
// tests pin everything the client owns:
//   * the manifest declares exactly one cover (the starred one) + order,
//   * the array stays in GRID order (identity / rebind depend on it),
//   * the declaration survives the durable record round-trip (restart),
//   * the wire form is typed (bool / int) while the record stays strings,
//   * legacy frozen manifests (no cover keys) still load and send unchanged,
//   * the owner's optimistic view leads with the starred photo until the
//     server has attached it.
import 'dart:convert';

import 'package:car_listing_app/features/sell/sell_media_identity.dart';
import 'package:car_listing_app/shared/listings/owner_pending_media_merge.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _photo(String path) => {'source': path};

Map<String, dynamic> _carData(int n, {int? primary}) => {
      'images': [for (var i = 0; i < n; i++) _photo('/draft/p$i.jpg')],
      'original_images': [for (var i = 0; i < n; i++) _photo('/draft/p$i.jpg')],
      if (primary != null) 'primary_image_index': primary,
    };

String _idOf(int i) =>
    SellMediaIdentity.forImageItem(_photo('/draft/p$i.jpg'), kind: 'listing')!;

List<int> _coverIndexes(List<Map<String, String>> manifest) => [
      for (var i = 0; i < manifest.length; i++)
        if (manifest[i]['is_cover'] == 'true') i,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildExpectedMedia declares the starred cover', () {
    test('1. star photo 3 of 5 -> photo 3 is the (only) cover, listed first', () {
      final m = SellMediaIdentity.buildExpectedMedia(_carData(5, primary: 2));
      expect(m, hasLength(5));
      expect(_coverIndexes(m), [2]);
      // Display order: cover first, everyone else keeps grid order.
      expect([for (final e in m) e['sort_order']], ['1', '2', '0', '3', '4']);
      // The array itself stays in GRID order (identity/rebind rely on it).
      expect([for (final e in m) e['client_media_id']],
          [for (var i = 0; i < 5; i++) _idOf(i)]);
    });

    test('2. star photo 3 then photo 2 -> photo 2 is the ONLY cover', () {
      final carData = _carData(5, primary: 2);
      expect(_coverIndexes(SellMediaIdentity.buildExpectedMedia(carData)), [2]);
      // The star button just rewrites the index.
      carData['primary_image_index'] = 1;
      final m = SellMediaIdentity.buildExpectedMedia(carData);
      expect(_coverIndexes(m), [1]);
      expect([for (final e in m) e['sort_order']], ['1', '0', '2', '3', '4']);
    });

    test('default (never starred) -> the first photo is the declared cover', () {
      final m = SellMediaIdentity.buildExpectedMedia(_carData(3));
      expect(_coverIndexes(m), [0]);
      expect([for (final e in m) e['sort_order']], ['0', '1', '2']);
    });

    test('garbled / out-of-range index falls back to the first photo', () {
      for (final bad in <Object?>[-1, 9, 'x', null]) {
        final carData = _carData(3);
        carData['primary_image_index'] = bad;
        expect(
          _coverIndexes(SellMediaIdentity.buildExpectedMedia(carData)),
          [0],
          reason: 'index=$bad',
        );
      }
    });

    test('cover on the last photo shifts the others down by one', () {
      final m = SellMediaIdentity.buildExpectedMedia(_carData(4, primary: 3));
      expect([for (final e in m) e['sort_order']], ['1', '2', '3', '0']);
      expect(_coverIndexes(m), [3]);
    });

    test('damage photos are ordered but never a cover; videos carry neither',
        () {
      final carData = <String, dynamic>{
        ..._carData(2, primary: 1),
        'damage_images': [_photo('/draft/d0.jpg'), _photo('/draft/d1.jpg')],
        'videos': ['/draft/v0.mp4'],
      };
      final m = SellMediaIdentity.buildExpectedMedia(carData);
      expect(m, hasLength(5));
      expect(_coverIndexes(m), [1], reason: 'only a listing photo is a cover');
      final damage = m.sublist(2, 4);
      expect([for (final e in damage) e['sort_order']], ['0', '1']);
      final video = m.last;
      expect(video['kind'], 'video');
      expect(video.containsKey('is_cover'), isFalse);
      expect(video.containsKey('sort_order'), isFalse);
    });

    test('the ids themselves are unchanged by the cover (no identity drift)',
        () {
      final a = SellMediaIdentity.buildExpectedMedia(_carData(4, primary: 0));
      final b = SellMediaIdentity.buildExpectedMedia(_carData(4, primary: 3));
      expect([for (final e in a) e['client_media_id']],
          [for (final e in b) e['client_media_id']]);
    });
  });

  group('wire payload / durable record', () {
    test('wire payload is typed: is_cover bool, sort_order int', () {
      final wire = SellMediaIdentity.expectedMediaWirePayload(
        SellMediaIdentity.buildExpectedMedia(_carData(3, primary: 1)),
      );
      expect(wire[1]['is_cover'], isTrue);
      expect(wire[0].containsKey('is_cover'), isFalse);
      expect([for (final e in wire) e['sort_order']], [1, 0, 2]);
      // Must be JSON-encodable exactly as sent.
      expect(() => json.encode(wire), returnsNormally);
    });

    test('3. the frozen manifest keeps the cover across a save/restart', () async {
      SharedPreferences.setMockInitialValues({});
      final frozen =
          SellMediaIdentity.buildExpectedMedia(_carData(5, primary: 2));
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: 'cover_restart',
          status: SellSubmissionStatus.inProgress,
          carId: 'car_1',
          carData: _carData(5, primary: 2),
          idempotencyKey: 'sell-create-cover_restart',
          createdAt: now,
          updatedAt: now,
          expectedMedia: frozen,
        ),
      );
      // A fresh read goes through toJson -> prefs string -> fromJson.
      final loaded = (await SellSubmissionStatePrefs.loadAll()).single;
      expect(loaded.expectedMedia, frozen);
      expect(_coverIndexes(loaded.expectedMedia!), [2]);
      expect(
        SellMediaIdentity.expectedMediaWirePayload(loaded.expectedMedia!),
        SellMediaIdentity.expectedMediaWirePayload(frozen),
      );
    });

    test('a legacy frozen manifest (no cover keys) loads and sends unchanged',
        () async {
      final legacy = <Map<String, String>>[
        {'client_media_id': 'img_a', 'kind': 'image'},
        {'client_media_id': 'img_b', 'kind': 'image'},
      ];
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: 'legacy',
          status: SellSubmissionStatus.inProgress,
          carData: const {},
          idempotencyKey: 'sell-create-legacy',
          createdAt: now,
          updatedAt: now,
          expectedMedia: legacy,
        ),
      );
      final loaded = (await SellSubmissionStatePrefs.loadAll()).single;
      expect(loaded.expectedMedia, legacy);
      expect(SellMediaIdentity.expectedMediaWirePayload(legacy), [
        {'client_media_id': 'img_a', 'kind': 'image'},
        {'client_media_id': 'img_b', 'kind': 'image'},
      ]);
    });

    test('rebinding a replaced photo into a frozen manifest keeps the cover slot',
        () {
      final frozen =
          SellMediaIdentity.buildExpectedMedia(_carData(3, primary: 1));
      // Photo 2 (the cover) is replaced by a different file.
      final replaced = <String, dynamic>{
        'images': [
          _photo('/draft/p0.jpg'),
          _photo('/draft/NEW.jpg'),
          _photo('/draft/p2.jpg'),
        ],
        'original_images': [
          _photo('/draft/p0.jpg'),
          _photo('/draft/NEW.jpg'),
          _photo('/draft/p2.jpg'),
        ],
        'primary_image_index': 1,
      };
      final rebound = SellMediaIdentity.rebindToFrozenManifest(replaced, frozen);
      expect(rebound.problem, isNull);
      // The replacement now derives the SAME id as the cover slot it took, so
      // the (frozen) cover declaration still points at a real upload.
      final nowIds = [
        for (final e in SellMediaIdentity.buildExpectedMedia(rebound.carData))
          e['client_media_id']
      ];
      expect(nowIds, [for (final e in frozen) e['client_media_id']]);
      expect(frozen[1]['is_cover'], 'true');
    });
  });

  group('owner pending merge leads with the starred photo', () {
    const draftId = 'draft_cover_merge';
    const carId = 'car_cover_merge';

    Future<List<Map<String, String>>> seed({int primary = 2}) async {
      SharedPreferences.setMockInitialValues({});
      final carData = _carData(4, primary: primary);
      final manifest = SellMediaIdentity.buildExpectedMedia(carData);
      final now = DateTime.now().millisecondsSinceEpoch;
      await SellSubmissionStatePrefs.upsert(
        SellSubmissionRecord(
          draftId: draftId,
          status: SellSubmissionStatus.inProgress,
          carId: carId,
          carData: carData,
          idempotencyKey: 'sell-create-$draftId',
          createdAt: now,
          updatedAt: now,
          expectedMedia: manifest,
        ),
      );
      return manifest;
    }

    test(
        '4. cover still processing while a sibling already attached: the '
        'starred local photo is first and the stand-in image_url is cleared',
        () async {
      await seed(primary: 2);
      // Photo 1 (not the cover) finished first and the server fell back to it.
      final car = <String, dynamic>{
        'id': carId,
        'image_url': 'https://cdn.example.com/p1.jpg',
        'images': [
          {
            'id': 11,
            'image_url': 'https://cdn.example.com/p1.jpg',
            'client_media_id': _idOf(1),
            'is_primary': false,
          },
        ],
      };
      final merged =
          await OwnerPendingMediaMerge.mergeIfOwner(car, isOwner: true);
      final images = merged['images'] as List;
      expect(ListingSource.of(images.first), '/draft/p2.jpg',
          reason: 'the starred photo leads');
      expect(merged['image_url'], '',
          reason: 'the sibling stand-in must not lead');
    });

    test('once the cover itself is attached the server order is untouched',
        () async {
      await seed(primary: 2);
      final car = <String, dynamic>{
        'id': carId,
        'image_url': 'https://cdn.example.com/p2.jpg',
        'images': [
          {
            'id': 12,
            'image_url': 'https://cdn.example.com/p2.jpg',
            'client_media_id': _idOf(2),
            'is_primary': true,
          },
        ],
      };
      final merged =
          await OwnerPendingMediaMerge.mergeIfOwner(car, isOwner: true);
      expect(merged['image_url'], 'https://cdn.example.com/p2.jpg');
      final images = merged['images'] as List;
      expect((images.first as Map)['id'], 12,
          reason: 'server cover stays first');
    });

    test('a non-owner is never touched', () async {
      await seed(primary: 2);
      final car = <String, dynamic>{'id': carId, 'images': <dynamic>[]};
      final merged =
          await OwnerPendingMediaMerge.mergeIfOwner(car, isOwner: false);
      expect(identical(merged, car), isTrue);
    });
  });
}

/// Tiny local helper so the test reads the same field the app does.
abstract final class ListingSource {
  static String of(dynamic item) =>
      item is Map ? (item['source'] ?? item['image_url'] ?? '').toString() : '$item';
}
