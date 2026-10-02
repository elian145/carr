// Real-device regression: "Some selected photos are not displaying
// correctly. They show the image placeholder instead of the actual
// photo."
//
// One confirmed contributing root cause (client-side,
// `lib/features/sell/sell_listing_media_upload.dart`):
// `_collectUploadedImageIds` used to zip the attach response's rows
// against the FULL original item list purely by POSITION. But
// `_uploadImagesViaAsyncJobs`'s `relPaths` (what actually gets attached)
// is a COMPACTED view that drops any item whose async job failed/timed
// out -- so once any image among several fails, every row from that
// point on gets zipped against the WRONG original item, and the true
// last-successful item gets no id mapping at all. Downstream,
// `_saveListingImageLayout` would then apply one photo's focus_y/order
// metadata to a DIFFERENT photo's `CarImage` row, and silently drop the
// layout update for the photo that got no id.
//
// This test drives `SellListingMediaUpload.uploadForCar` with 4 images
// where the 3rd photo's processing job permanently fails, and proves the
// `PUT /cars/<id>/images/layout` call ends up with the CORRECT id for
// every surviving photo, never a swapped/missing one.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _jsonOk(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('image_partial_fail_');
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    await ApiService.setTokens(
      accessToken: 'test_access_token',
      refreshToken: 'test_refresh_token',
    );
  });

  tearDown(() async {
    await ApiService.clearTokens();
    ApiService.testHttpClient = null;
    setRuntimeApiBaseOverride(null);
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'four images, the 3rd permanently fails processing: the layout call '
    'assigns the CORRECT server id to each of the 3 surviving photos -- '
    'no photo gets a sibling\'s id, and the last successful photo (4th) '
    'is never silently dropped from the layout update',
    () async {
      const carId = 'car_partial_img_1';
      final img1 = File('${tempDir.path}/img1.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 1));
      final img2 = File('${tempDir.path}/img2.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 2));
      final img3 = File('${tempDir.path}/img3.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 3));
      final img4 = File('${tempDir.path}/img4.jpg')
        ..writeAsBytesSync(List<int>.filled(16, 4));

      // Map items (not raw path strings) each carrying a UNIQUE `focus_y`
      // -- this is what makes it possible for this test to observe WHICH
      // original photo the layout call's `id` actually ended up
      // associated with, since the layout payload itself carries no
      // `source`/`image_url`, only `id`/`order`/`focus_y`/etc.
      final carData = <String, dynamic>{
        'images': [
          {'source': img1.path, 'focus_y': 0.11},
          {'source': img2.path, 'focus_y': 0.22},
          {'source': img3.path, 'focus_y': 0.33},
          {'source': img4.path, 'focus_y': 0.44},
        ],
        'videos': <dynamic>[],
        'damage_images': <dynamic>[],
      };

      Map<String, dynamic>? layoutBody;

      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;

        if (method == 'GET' &&
            RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
          return _jsonOk({
            'car': {'id': carId, 'images': <dynamic>[], 'videos': <dynamic>[]},
          });
        }

        final enqueueMatch =
            RegExp(r'^/api/cars/([^/]+)/images$').firstMatch(path);
        if (method == 'POST' && enqueueMatch != null) {
          final bodyText = latin1.decode(request.bodyBytes);
          final fileCount =
              RegExp('name="images"').allMatches(bodyText).length;
          final jobIds = [
            for (var i = 0; i < fileCount; i++) 'job_${i + 1}',
          ];
          return _jsonOk({'job_ids': jobIds}, 202);
        }

        if (method == 'GET' && path.startsWith('/api/jobs/')) {
          final jobId = path.substring('/api/jobs/'.length);
          if (jobId == 'job_3') {
            // img3's job permanently fails.
            return _jsonOk({'task_id': jobId, 'state': 'FAILURE'});
          }
          return _jsonOk({
            'task_id': jobId,
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/$jobId.jpg'},
          });
        }

        final attachMatch =
            RegExp(r'^/api/cars/([^/]+)/images/attach$').firstMatch(path);
        if (method == 'POST' && attachMatch != null) {
          final decoded = json.decode(request.body) as Map;
          final paths = List<String>.from(decoded['paths'] as List);
          // Backend assigns SEQUENTIAL new ids, in the SAME order as
          // `paths` (which only contains the 3 surviving rel_paths --
          // job_3/img3 was never in this list at all).
          final rows = <Map<String, dynamic>>[];
          for (var i = 0; i < paths.length; i++) {
            rows.add({'id': 200 + i, 'image_url': paths[i]});
          }
          return _jsonOk({'images': rows}, 201);
        }

        final layoutMatch =
            RegExp(r'^/api/cars/([^/]+)/images/layout$').firstMatch(path);
        if (method == 'PUT' && layoutMatch != null) {
          layoutBody = json.decode(request.body) as Map<String, dynamic>;
          return _jsonOk({'message': 'ok'});
        }

        return _jsonOk({'cars': []});
      });

      await SellListingMediaUpload.uploadForCar(
        carId: carId,
        carData: carData,
      );

      expect(layoutBody, isNotNull, reason: 'a layout call must happen '
          'for the 3 surviving photos');
      final rows = List<Map<String, dynamic>>.from(
        (layoutBody!['images'] as List).cast<Map<String, dynamic>>(),
      );

      // job_1 -> rel_path job_1.jpg -> attach row id 200 (paths[0])
      // job_2 -> rel_path job_2.jpg -> attach row id 201 (paths[1])
      // job_3 -> FAILED, never attached, never in the layout at all
      // job_4 -> rel_path job_4.jpg -> attach row id 202 (paths[2])
      final byUrlSuffix = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        byUrlSuffix[row['id'].toString()] = row;
      }

      expect(
        rows.length,
        3,
        reason: 'exactly the 3 surviving photos must appear in the '
            'layout call -- the permanently-failed 3rd photo has no id '
            'and must be skipped, never crash or silently corrupt a '
            'sibling row',
      );

      final idsPresent = rows.map((r) => r['id']).toSet();
      expect(
        idsPresent,
        {200, 201, 202},
        reason: 'every surviving photo (img1, img2, img4) must get its '
            'OWN correct id -- img4 must not be silently dropped, and no '
            'id must be reused/duplicated across two different photos',
      );

      // The BUG this test guards against: with a naive positional zip
      // against the FULL original item list, img3 (index 2, the failed
      // one) would incorrectly receive id 202 -- the row that actually
      // belongs to img4 (index 3) -- because the attach response only
      // has 3 rows (img3 was excluded from what was actually attached).
      // Each `focus_y` is UNIQUE per original photo, so the id assigned
      // to img4's own `focus_y` (0.44) reveals whether the mapping used
      // the correct original item.
      final rowForImg4Focus = rows.firstWhere(
        (r) => (r['focus_y'] as num).toDouble() == 0.44,
        orElse: () => const {},
      );
      expect(
        rowForImg4Focus['id'],
        202,
        reason: 'img4 (focus_y=0.44) must be assigned ITS OWN id (202) -- '
            'the exact real-device bug this test guards against is img3 '
            '(the permanently-failed photo) incorrectly stealing this id '
            'instead, via a naive positional zip against the response',
      );
      final rowForImg3Focus = rows.firstWhere(
        (r) => (r['focus_y'] as num).toDouble() == 0.33,
        orElse: () => const {},
      );
      expect(
        rowForImg3Focus,
        isEmpty,
        reason: 'img3 permanently failed processing and was never '
            'attached -- it must never appear in the layout call at all, '
            'under any id',
      );
    },
  );
}
