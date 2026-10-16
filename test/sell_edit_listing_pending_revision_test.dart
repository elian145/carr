// Editing a PUBLISHED (Active) listing.
//
// Root cause that these tests pin down: for an edit, the submission record
// is created with `carId == editListingId`, and `_runSubmission` only ran its
// field update (`PUT /api/cars/<id>`) inside `if (carId.isEmpty)`. So for an
// edit the PUT was skipped from the very first attempt and the owner's edits
// never reached the server -- only their media did.
//
// The server now stores the PUT as a pending revision that an admin must
// approve (`submitted_for_review: true`); the client must surface that.
import 'dart:convert';
import 'dart:io';

import 'package:car_listing_app/features/sell/pending_sell_submission_service.dart';
import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:car_listing_app/shared/prefs/sell_submission_state_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDocsPathProvider extends PathProviderPlatform {
  _FakeDocsPathProvider(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Map<String, dynamic> _carData({
  List<dynamic>? images,
  String description = 'Clean car',
}) => {
  'brand': 'toyota',
  'model': 'camry',
  'trim': 'base',
  'year': '2021',
  'mileage': '10000',
  'price': '15000',
  'condition': 'used',
  'transmission': 'automatic',
  'fuel_type': 'gasoline',
  'color': 'black',
  'body_type': 'sedan',
  'seating': '5',
  'drive_type': 'fwd',
  'city': 'baghdad',
  'contact_phone': '07701234567',
  'description': description,
  'images': images ?? <dynamic>[],
  'videos': <dynamic>[],
  'damage_images': <dynamic>[],
  'server_transcode_videos': <dynamic>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const editId = 'active_car_1';

  http.Response jsonOk(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        json.encode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('edit_revision_');
    final docsDir = Directory('${tempDir.path}/docs')
      ..createSync(recursive: true);
    PathProviderPlatform.instance = _FakeDocsPathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    debugSellSubmissionRetryBackoffOverride = (_) => Duration.zero;
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
    debugSellSubmissionRetryBackoffOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'an edit of an Active listing really sends PUT /api/cars/<id> '
    '(regression: it used to be skipped) and reports that the changes '
    'were submitted for review',
    () async {
      final puts = <Map<String, dynamic>>[];
      var creates = 0;
      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'POST' && path == '/api/cars') {
          creates++;
          return jsonOk({'car': {'id': 'nope'}}, 201);
        }
        if (method == 'PUT' && path == '/api/cars/$editId') {
          puts.add(Map<String, dynamic>.from(json.decode(request.body) as Map));
          // The server only skips its legacy auto-finalize of idle drafts for
          // builds that announce they understand moderation.
          expect(request.headers['X-Carnet-Review-Aware'], '1');
          return jsonOk({
            'message': 'Your changes have been submitted for review.',
            'submitted_for_review': true,
            'car': {'id': editId, 'status': 'active', 'images': []},
          });
        }
        if (method == 'GET' && path == '/api/cars/$editId') {
          return jsonOk({
            'car': {
              'id': editId,
              'status': 'active',
              'images': [],
              'videos': [],
              'pending_revision': {'status': 'pending'},
            },
          });
        }
        return jsonOk({'cars': []});
      });

      final result = await PendingSellSubmissionService.instance.submit(
        draftId: 'edit_text_only',
        carData: _carData(description: 'Updated description'),
        editListingId: editId,
      );

      expect(result, isNotNull);
      expect(result!.id, editId);
      expect(creates, 0, reason: 'an edit must never create a second listing');
      expect(puts, hasLength(1), reason: 'the field update must be sent once');
      expect(puts.single['description'], 'Updated description');
      expect(puts.single.containsKey('expected_media'), isFalse);
      expect(result.pendingReview, isFalse,
          reason: 'the listing itself stays public');
      expect(result.editSubmittedForReview, isTrue);
      expect(await SellSubmissionStatePrefs.load('edit_text_only'), isNull);
    },
  );

  test(
    'clearing an optional field (empty description) is sent as an explicit '
    'null so the removal takes effect on the pending edit',
    () async {
      Map<String, dynamic>? put;
      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'PUT' && path == '/api/cars/$editId') {
          put = Map<String, dynamic>.from(json.decode(request.body) as Map);
          return jsonOk({
            'submitted_for_review': true,
            'car': {'id': editId, 'status': 'active'},
          });
        }
        if (method == 'GET' && path == '/api/cars/$editId') {
          return jsonOk({
            'car': {'id': editId, 'status': 'active', 'images': []},
          });
        }
        return jsonOk({'cars': []});
      });

      await PendingSellSubmissionService.instance.submit(
        draftId: 'edit_clear_description',
        carData: _carData(description: ''),
        editListingId: editId,
      );

      expect(put, isNotNull);
      expect(put!.containsKey('description'), isTrue);
      expect(put!['description'], isNull);
    },
  );

  test(
    'new photos of an edit are declared in expected_media on the PUT so the '
    'admin cannot approve the revision before they finish processing',
    () async {
      final imagePath = p.join(tempDir.path, 'new_photo.jpg');
      File(imagePath).writeAsBytesSync(List<int>.filled(16, 3));
      Map<String, dynamic>? put;
      ApiService.testHttpClient = MockClient((request) async {
        final method = request.method.toUpperCase();
        final path = request.url.path;
        if (method == 'PUT' && path == '/api/cars/$editId') {
          put = Map<String, dynamic>.from(json.decode(request.body) as Map);
          return jsonOk({
            'submitted_for_review': true,
            'car': {'id': editId, 'status': 'active'},
          });
        }
        if (method == 'GET' && path == '/api/cars/$editId') {
          return jsonOk({
            'car': {
              'id': editId,
              'status': 'active',
              'images': [],
              'videos': [],
              'pending_revision': {
                'status': 'pending',
                'car': {'id': editId, 'images': [], 'videos': []},
              },
            },
          });
        }
        if (method == 'POST' && path == '/api/cars/$editId/images') {
          return jsonOk({'job_ids': <String>['job_1']}, 202);
        }
        if (method == 'GET' && path == '/api/jobs/job_1') {
          return jsonOk({
            'task_id': 'job_1',
            'state': 'SUCCESS',
            'result': {'rel_path': 'uploads/car_photos/job_1.jpg'},
          });
        }
        if (method == 'POST' && path == '/api/cars/$editId/images/attach') {
          return jsonOk({
            'images': [
              {'id': 1, 'image_url': 'uploads/car_photos/job_1.jpg'},
            ],
          }, 201);
        }
        return jsonOk({'cars': []});
      });

      final result = await PendingSellSubmissionService.instance.submit(
        draftId: 'edit_new_photo',
        carData: _carData(images: [imagePath]),
        editListingId: editId,
      );

      expect(result, isNotNull);
      expect(put, isNotNull);
      final expected = put!['expected_media'];
      expect(expected, isA<List>());
      expect((expected as List), hasLength(1));
      expect((expected.single as Map)['kind'], 'image');
      expect((expected.single as Map)['client_media_id'], isNotEmpty);
    },
  );
}
