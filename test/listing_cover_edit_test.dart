// Editing a published listing: the seller stars a different photo and the new
// cover must reach the server (`PUT .../images/primary` + `.../images/layout`)
// so it persists, in cover-first order, with exactly one primary.
//
// Edit mode has no `expected_media` manifest, so it keeps using the
// synchronous primary/layout calls (unchanged). The NEW-listing path must NOT
// make those calls (the server applies the manifest-declared cover itself) --
// pinned in `sell_submission_integrity_test.dart`.
import 'dart:convert';

import 'package:car_listing_app/features/sell/sell_listing_media_upload.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EditServer {
  _EditServer(this.images);

  /// What the server currently holds (cover first), as `GET car` returns it.
  final List<Map<String, dynamic>> images;
  final calls = <String>[];
  Map<String, dynamic>? primaryBody;
  Map<String, dynamic>? layoutBody;

  http.Response _json(Object body, [int status = 200]) => http.Response(
    json.encode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;
    calls.add('$method $path');

    if (method == 'PUT' && path.endsWith('/images/primary')) {
      primaryBody = Map<String, dynamic>.from(json.decode(request.body) as Map);
      final url = (primaryBody!['image_url'] ?? '').toString();
      for (final i in images) {
        i['is_primary'] = i['image_url'] == url;
      }
      images.sort(
        (a, b) => (b['is_primary'] == true ? 1 : 0) - (a['is_primary'] == true ? 1 : 0),
      );
      return _json({'message': 'Primary image updated', 'image_url': url});
    }
    if (method == 'PUT' && path.endsWith('/images/layout')) {
      layoutBody = Map<String, dynamic>.from(json.decode(request.body) as Map);
      return _json({'images': layoutBody!['images']});
    }
    if (method == 'GET' && RegExp(r'^/api/cars/[^/]+$').hasMatch(path)) {
      return _json({
        'car': {'id': 'car_9', 'images': images, 'videos': <dynamic>[]},
      });
    }
    return _json({'images': images});
  }
}

Map<String, dynamic> _serverImage(int id, {bool primary = false}) => {
  'id': id,
  'image_url': 'https://cdn.example.com/uploads/photo$id.jpg',
  'is_primary': primary,
  'order': id - 1,
  'kind': 'listing',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _EditServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    server = _EditServer([
      _serverImage(1, primary: true),
      _serverImage(2),
      _serverImage(3),
    ]);
    ApiService.testHttpClient = MockClient(server.handle);
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
  });

  Map<String, dynamic> editCarData(int primaryIndex) => {
    'images': [for (final i in server.images) Map<String, dynamic>.from(i)],
    'videos': <dynamic>[],
    'damage_images': <dynamic>[],
    'primary_image_index': primaryIndex,
  };

  test('8. edit: starring photo 3 sends it as the primary and cover-first '
      'layout (one primary, ids intact, nothing lost)', () async {
    await SellListingMediaUpload.uploadForCar(
      carId: 'car_9',
      carData: editCarData(2),
    );

    expect(server.primaryBody, isNotNull, reason: 'primary must be updated');
    expect(
      server.primaryBody!['image_url'],
      'https://cdn.example.com/uploads/photo3.jpg',
    );

    final rows = (server.layoutBody!['images'] as List).cast<Map>();
    expect([for (final r in rows) r['id']], [3, 1, 2], reason: 'cover first');
    expect([for (final r in rows) r['order']], [0, 1, 2]);
    expect([for (final r in rows) r['is_primary']], [true, false, false]);
    expect(rows.where((r) => r['is_primary'] == true), hasLength(1));
  });

  test('8b. edit: changing the star again moves the single cover', () async {
    await SellListingMediaUpload.uploadForCar(
      carId: 'car_9',
      carData: editCarData(2),
    );
    // The seller reopens, stars photo 2 (index 1 of what the server now holds).
    server.layoutBody = null;
    server.primaryBody = null;
    final reopened = editCarData(1);
    final photo2Id = reopened['images'][1]['id'];
    await SellListingMediaUpload.uploadForCar(carId: 'car_9', carData: reopened);

    final rows = (server.layoutBody!['images'] as List).cast<Map>();
    expect(rows.first['id'], photo2Id);
    expect(rows.where((r) => r['is_primary'] == true), hasLength(1));
    expect(rows.first['is_primary'], isTrue);
  });

  test('8c. edit: an unchanged cover (index 0) re-sends the same cover and '
      'does not disturb ordering', () async {
    await SellListingMediaUpload.uploadForCar(
      carId: 'car_9',
      carData: editCarData(0),
    );
    final rows = (server.layoutBody!['images'] as List).cast<Map>();
    expect([for (final r in rows) r['id']], [1, 2, 3]);
    expect([for (final r in rows) r['is_primary']], [true, false, false]);
  });

  test('the edit snapshot picks the cover the server reports as the primary '
      '(first gallery image)', () {
    final snap = listingToSellDraftSnapshot(
      {
        'id': 'car_9',
        'image_url': 'https://cdn.example.com/uploads/photo3.jpg',
        'images': [
          _serverImage(3, primary: true),
          _serverImage(1),
          _serverImage(2),
        ],
      },
      contactPhoneFallback: '07700000000',
    );
    final carData = Map<String, dynamic>.from(snap['carData'] as Map);
    final images = carData['images'] as List;
    final idx = carData['primary_image_index'] as int;
    expect((images[idx] as Map)['id'], 3);
  });
}
