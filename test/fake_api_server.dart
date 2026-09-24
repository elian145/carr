import 'dart:async';
import 'dart:convert';

import 'package:car_listing_app/services/api_service.dart';
import 'package:car_listing_app/services/config.dart';
import 'package:car_listing_app/shared/auth/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory API stub for widget/smoke tests (no loopback [HttpServer]).
///
/// Binds [ApiService.testHttpClient] to a [MockClient] so Flutter's test
/// binding does not intercept loopback HTTP with status 400.
class FakeApiServer {
  FakeApiServer._();

  static MockClient? _client;
  static String? _expectedBearer;

  /// When true, GET/sync saved-searches return an empty list (empty-state tests).
  static bool emptySavedSearches = false;

  /// OOM-fix follow-up regression coverage: records every
  /// `POST /api/process-car-images` request seen, in call order --
  /// `{'async': bool, 'skip_blur': bool, 'file_count': int}`. Used to prove
  /// production Sell prestage always sends `async=1` (and never hits the
  /// synchronous branch). Reset by [stop].
  static final List<Map<String, dynamic>> processCarImagesCalls = [];

  /// Per-call override for `POST /api/process-car-images` (any mode).
  /// Return an [http.Response] to force a specific status/body (e.g. a 400
  /// validation rejection or a malformed job-id list), or `null`/leave
  /// unset to fall through to the default stub (202 + one job id per
  /// uploaded file when `async=1`; 200 + `processed_images` otherwise).
  /// Cleared by [stop].
  static http.Response? Function(http.Request request)?
      processCarImagesOverride;

  /// Monotonically increasing counter used to generate unique job ids for
  /// the default `POST /api/process-car-images?async=1` stub. Reset by
  /// [stop].
  static int _processCarImagesJobIdSeq = 0;

  /// Per-job-id response queue for `GET /api/jobs/<job_id>` polling.
  /// Each entry is consumed in order (the last entry repeats once the
  /// queue is down to one) -- lets a test simulate a PENDING -> SUCCESS/
  /// FAILURE sequence deterministically, with no real delays. The default
  /// `POST /api/process-car-images?async=1` stub seeds every job id it
  /// returns with a single `SUCCESS` entry unless a test has already
  /// queued something for that id first. Cleared by [stop].
  static final Map<String, List<Map<String, dynamic>>> jobStatusQueue = {};

  /// Records every `GET /api/jobs/<job_id>` poll, in call order. Reset by
  /// [stop].
  static final List<String> jobStatusPollCalls = [];

  /// Crude multipart-part counter for the fake server's own request
  /// inspection (not a general-purpose parser): counts
  /// `name="<fieldName>"` occurrences in the raw multipart body, which
  /// corresponds 1:1 with the number of files [MultipartRequest] attached
  /// under that field name.
  static int _countMultipartParts(http.Request request, String fieldName) {
    final contentType = request.headers['content-type'] ?? '';
    if (!contentType.contains('multipart/form-data')) return 0;
    final bodyStr = String.fromCharCodes(request.bodyBytes);
    return RegExp('name="$fieldName"').allMatches(bodyStr).length;
  }

  /// CarNet V1 fix 4 regression coverage: when set, `POST
  /// /api/auth/phone/verify` returns this response instead of the default
  /// stub success -- used to simulate the backend's
  /// `403 {"code": "account_deactivated"}` response for a deactivated
  /// account's otherwise-correct OTP. Reset by [stop].
  static http.Response Function()? phoneVerifyOverride;

  /// Counts plain `GET /api/cars/<id>` requests (car-detail fetches).
  ///
  /// Used by chat-navigation tests (Fix A) to prove `ChatConversationPage`
  /// does/does not fall back to `ApiService.getCar()` depending on whether a
  /// usable `initialListingPreview` was forwarded from `ChatListPage`. Reset
  /// this to 0 at the start of a test that relies on it.
  static int carDetailFetchCount = 0;

  /// F-01/B-02 regression coverage: per-car-id override for a plain
  /// `GET /api/cars/<id>` (car-detail) request, keyed by the raw id path
  /// segment. Return an [http.Response] to force a specific status/body
  /// (404/5xx/429/malformed/empty), or throw to simulate a transport
  /// failure or timeout. Falls through to the default 200 stub when a car
  /// id has no override. Cleared by [stop].
  static final Map<String, http.Response Function()> carDetailOverrides =
      <String, http.Response Function()>{};

  /// F-07 regression coverage: per-car-id override for
  /// `GET /api/cars/<id>/contact` (the contact-phone-reveal endpoint).
  /// Return an [http.Response] to force a specific status/body (401/429/
  /// 500/malformed), or throw to simulate a transport failure or timeout.
  /// Falls through to the default stub (a car with no contact phone) when a
  /// car id has no override. Cleared by [stop].
  static final Map<String, http.Response Function()> carContactOverrides =
      <String, http.Response Function()>{};

  /// CarNet V1 batch 2 (rejected/hidden vs pending listing status UX)
  /// regression coverage: when set, `GET /api/user/my-listings?status=X`
  /// returns `byStatus[X] ?? []` (`byStatus['']` for the unfiltered "All"
  /// tab) instead of the generic empty-list stub. Cleared by [stop].
  static Map<String, List<Map<String, dynamic>>>? myListingsByStatus;

  /// CarNet V1 batch 2 (favorites pagination) regression coverage: when
  /// set, `GET /api/user/favorites` paginates this full item list by the
  /// request's `page`/`per_page` query params instead of returning the
  /// generic empty-list stub. Cleared by [stop].
  static List<Map<String, dynamic>>? favoritesAllItems;

  /// Release-candidate fix 2 (chat pagination direction) regression
  /// coverage: when set, `GET /api/chat/<id>/messages` serves this full,
  /// ascending-chronological-order conversation from an in-memory list and
  /// mirrors the real backend contract (kk/routes/chat.py::get_messages) --
  /// no `before` cursor => newest `per_page` messages; `before=<iso ts>` =>
  /// the next-older page -- instead of the generic empty-list stub.
  /// Cleared by [stop].
  static List<Map<String, dynamic>>? chatMessagesAllItems;

  /// Records every `before` query value seen on
  /// `GET /api/chat/<id>/messages`, in call order (empty string when the
  /// request had no `before` cursor). Reset by [stop].
  static final List<String> chatMessagesRequestedBefore = [];

  /// Records every `page` value requested via
  /// `GET /api/user/favorites?page=N`, in call order. Reset by [stop].
  static final List<int> favoritesRequestedPages = [];

  /// F-04 regression coverage: when set, `GET /api/user/favorites` awaits
  /// this completer instead of returning the default stub immediately, so
  /// tests can deterministically control exactly when the response resolves
  /// relative to widget disposal (no timers/sleeps involved). Cleared by
  /// [stop].
  static Completer<http.Response>? favoritesResponseGate;

  /// F-06 regression coverage: when set, `GET /api/cars/<id>` (car-detail)
  /// awaits this completer instead of returning the default/overridden
  /// stub immediately, so tests can deterministically control exactly when
  /// the response resolves relative to widget disposal/cancellation (no
  /// timers/sleeps involved). Cleared by [stop].
  static Completer<http.Response>? carDetailResponseGate;

  /// F-06 regression coverage: when set, `POST /api/auth/refresh` awaits
  /// this completer instead of returning the default stub immediately, so
  /// a test can cancel a token specifically while a 401-triggered refresh
  /// is still in flight. Cleared by [stop].
  static Completer<http.Response>? authRefreshGate;

  /// Regression coverage for the Home-feed search race-condition fix: when
  /// set, `GET /api/cars` requests whose `q` query parameter matches a key
  /// in this map await that key's [Completer] instead of resolving
  /// immediately. Lets a test control the exact order in which two
  /// overlapping searches' responses arrive — e.g. an older, broader
  /// search's response completing *after* a newer, narrower one — without
  /// timers/sleeps. A `q`-less request (plain feed load) is keyed by `''`.
  /// Falls through to the default `/api/cars` stub when the current
  /// request's `q` has no entry. Cleared by [stop].
  static Map<String, Completer<http.Response>>? carsQueryGates;

  /// Records every `q` value seen on `GET /api/cars`, in call order
  /// (`''` for a request with no `q`). Reset by [stop]. Lets a test assert
  /// exactly which searches were actually sent, and in what order.
  static final List<String> carsRequestedQueries = [];

  /// Regression coverage for the client-side exact-model filter fix
  /// (traced "Land Cruiser" -> "Land Cruiser Prado" bug): when set, called
  /// for every `GET /api/cars` request with its full query-parameter map
  /// (checked after [carsQueryGates]). Return an [http.Response] to force a
  /// specific response -- e.g. to simulate the real backend's
  /// `Car.model.ilike('%<model>%')` substring match returning rows outside
  /// the exact requested `model` -- or `null` to fall through to the
  /// default `/api/cars` stub. Cleared by [stop].
  static http.Response? Function(Map<String, String> queryParameters)?
      carsResponseOverride;

  /// BE-18: records the `Idempotency-Key` header (or null if absent) seen on
  /// every `POST /api/chat/<id>/send*` request, in call order. Used to prove
  /// the same key is threaded through from `ApiService`/`OutgoingChatSendService`
  /// down to the actual HTTP request. Reset at the start of a test that relies
  /// on it.
  static final List<String?> chatSendIdempotencyKeys = [];

  /// B-07 regression coverage: when set, `GET /api/user/notifications`
  /// returns this list (wrapped in the real `{notifications, pagination}`
  /// shape) instead of the default empty stub. Cleared by [stop].
  static List<Map<String, dynamic>>? notificationsOverride;

  /// B-04 regression coverage: when set, `GET /api/user/notifications`
  /// calls this instead of returning the default/[notificationsOverride]
  /// 200 stub — return an [http.Response] to force a specific status (e.g.
  /// 500) or throw to simulate a transport failure/timeout. Takes priority
  /// over [notificationsOverride] while set. Cleared by [stop].
  static http.Response Function()? notificationsGetOverride;

  /// B-07 regression coverage: records every notification id marked read
  /// via `PATCH /api/user/notifications/<id>/read`, in call order. Reset at
  /// the start of a test that relies on it, cleared by [stop].
  static final List<String> markNotificationReadCalls = [];

  /// F-11 regression coverage: per-call override for
  /// `POST /api/chat/<id>/send*` (any send variant — text/image/video/
  /// audio/media_group all contain `/send` in their path). Called with the
  /// raw request (including whatever `Idempotency-Key` header it carried)
  /// and the 0-based call index for this endpoint (across all send
  /// variants) seen so far. Return an [http.Response] to force a specific
  /// status/body, return `null` to fall through to the default 201 success
  /// stub, or throw to simulate a transport failure/timeout. Cleared by
  /// [stop].
  static http.Response? Function(http.Request request, int callIndex)?
      chatSendOverride;

  /// Number of `POST /api/chat/<id>/send*` requests observed so far (any
  /// variant). Reset by [stop]. Useful to assert exactly how many attempts
  /// a retry made.
  static int chatSendCallCount = 0;

  /// CarNet V1 batch 2 (edit listing: delete photos/videos) regression
  /// coverage: records every `DELETE /api/cars/<carId>/images/<imageId>`
  /// call as `"<carId>/<imageId>"`, in call order. Reset by [stop].
  static final List<String> deletedCarImageCalls = [];

  /// Same as [deletedCarImageCalls] but for
  /// `DELETE /api/cars/<carId>/videos/<videoId>`. Reset by [stop].
  static final List<String> deletedCarVideoCalls = [];

  /// Per-call override for `DELETE /api/cars/<carId>/images/<imageId>`.
  /// Called with `(carId, imageId)`; return an [http.Response] to force a
  /// specific status/body (e.g. a 400 last-photo-invariant rejection), or
  /// `null` to fall through to the default 200 success stub. Cleared by
  /// [stop].
  static http.Response? Function(String carId, String imageId)?
      deleteCarImageOverride;

  /// Same as [deleteCarImageOverride] but for the video-delete endpoint.
  /// Cleared by [stop].
  static http.Response? Function(String carId, String videoId)?
      deleteCarVideoOverride;

  /// When set, protected routes reject requests whose Authorization header
  /// is not `Bearer <token>`.
  static void expectBearer(String? token) {
    final t = (token ?? '').trim();
    _expectedBearer = t.isEmpty ? null : t;
  }

  static http.Response? _authGuard(http.Request request) {
    final expected = _expectedBearer;
    if (expected == null) return null;
    final auth = (request.headers['authorization'] ??
            request.headers['Authorization'] ??
            '')
        .trim();
    if (auth != 'Bearer $expected') {
      return _json(401, {'message': 'Invalid token'});
    }
    return null;
  }

  /// Starts the stub once per isolate (safe for parallel `flutter test`).
  static Future<void> ensureStarted() async {
    if (_client != null) return;
    TokenStore.testMode = true;
    setRuntimeApiBaseOverride('http://127.0.0.1:1');
    _client = MockClient(_handle);
    ApiService.testHttpClient = _client;
  }

  static Future<void> stop() async {
    ApiService.testHttpClient = null;
    _client = null;
    _expectedBearer = null;
    emptySavedSearches = false;
    carDetailFetchCount = 0;
    carDetailOverrides.clear();
    carContactOverrides.clear();
    favoritesResponseGate = null;
    carDetailResponseGate = null;
    authRefreshGate = null;
    chatSendIdempotencyKeys.clear();
    chatSendOverride = null;
    chatSendCallCount = 0;
    notificationsOverride = null;
    notificationsGetOverride = null;
    markNotificationReadCalls.clear();
    deletedCarImageCalls.clear();
    deletedCarVideoCalls.clear();
    deleteCarImageOverride = null;
    deleteCarVideoOverride = null;
    favoritesAllItems = null;
    favoritesRequestedPages.clear();
    myListingsByStatus = null;
    chatMessagesAllItems = null;
    chatMessagesRequestedBefore.clear();
    phoneVerifyOverride = null;
    carsQueryGates = null;
    carsRequestedQueries.clear();
    carsResponseOverride = null;
    processCarImagesCalls.clear();
    processCarImagesOverride = null;
    _processCarImagesJobIdSeq = 0;
    jobStatusQueue.clear();
    jobStatusPollCalls.clear();
    TokenStore.testMode = false;
    TokenStore.resetForTests();
    setRuntimeApiBaseOverride(null);
  }

  static Future<http.Response> _handle(http.Request request) async {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    final gate = favoritesResponseGate;
    if (gate != null && method == 'GET' && path == '/api/user/favorites') {
      return gate.future;
    }

    final carGate = carDetailResponseGate;
    if (carGate != null &&
        method == 'GET' &&
        path.startsWith('/api/cars/') &&
        path.substring('/api/cars/'.length).split('/').length == 1) {
      return carGate.future;
    }

    final refreshGate = authRefreshGate;
    if (refreshGate != null && method == 'POST' && path == '/api/auth/refresh') {
      return refreshGate.future;
    }

    if (method == 'GET' && path == '/api/cars') {
      final q = request.url.queryParameters['q'] ?? '';
      carsRequestedQueries.add(q);
      final gates = carsQueryGates;
      if (gates != null) {
        final gate = gates[q];
        if (gate != null) return gate.future;
      }
      final override = carsResponseOverride;
      if (override != null) {
        final forced = override(request.url.queryParameters);
        if (forced != null) return forced;
      }
    }

    final response = _responseFor(request);
    return response ?? http.Response('Not found', 404);
  }

  static http.Response _json(int status, Object body) {
    return http.Response(
      json.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static Map<String, dynamic> _sampleCar(String id) => {
        'id': id,
        'title': 'Test car',
        'brand': 'toyota',
        'model': 'camry',
        'year': 2020,
        'price': 10000,
        'currency': 'USD',
        'location': 'Erbil',
        'image_url': '',
        'images': <dynamic>[],
        'videos': <dynamic>[],
        'seller': {'id': 'seller_1', 'username': 'seller'},
      };

  static List<Map<String, dynamic>> _sampleChats() => [
        {
          'conversation_id': 1,
          'car_id': 'list_car_1',
          'car_title': 'Test car',
          'car_brand': 'toyota',
          'car_model': 'camry',
          'car_year': 2020,
          'other_user': {'id': 'buyer_1', 'name': 'Test Buyer'},
          'last_message': {
            'id': 'msg_stub_1',
            'content': 'Hello from stub',
            'message_type': 'text',
            'created_at': '2026-01-01T12:00:00.000Z',
            'sender_id': 'buyer_1',
          },
          'unread_count': 1,
        },
      ];

  static http.Response? _responseFor(http.Request request) {
    final method = request.method.toUpperCase();
    final path = request.url.path;

    if (path == '/health') {
      return _json(200, {'status': 'ok'});
    }

    if (!path.startsWith('/api/')) {
      return null;
    }

    if (path.startsWith('/api/cars/') && path.length > '/api/cars/'.length) {
      final segments = path.substring('/api/cars/'.length).split('/');
      final id = segments.first;
      if (segments.length > 1 && segments[1] == 'favorite') {
        if (method == 'POST') {
          return _json(200, {'is_favorited': true, 'message': 'added'});
        }
        return _json(200, {'is_favorited': false});
      }
      if (segments.length > 1 && segments[1] == 'images' && method == 'POST') {
        return _json(201, {
          'images': <dynamic>[],
          'image_url': 'https://example.com/car.jpg',
        });
      }
      if (segments.length > 1 && segments[1] == 'videos' && method == 'POST') {
        return _json(201, {'videos': <dynamic>[], 'message': 'stub'});
      }
      // CarNet V1 batch 2 (edit listing: delete photos/videos) regression
      // coverage: DELETE /api/cars/<id>/images/<image_id> and
      // /api/cars/<id>/videos/<video_id>.
      if (segments.length > 2 && segments[1] == 'images' && method == 'DELETE') {
        final imageId = segments[2];
        deletedCarImageCalls.add('$id/$imageId');
        final override = deleteCarImageOverride;
        if (override != null) {
          final forced = override(id, imageId);
          if (forced != null) return forced;
        }
        return _json(200, {'message': 'Image deleted', 'image_url': ''});
      }
      if (segments.length > 2 && segments[1] == 'videos' && method == 'DELETE') {
        final videoId = segments[2];
        deletedCarVideoCalls.add('$id/$videoId');
        final override = deleteCarVideoOverride;
        if (override != null) {
          final forced = override(id, videoId);
          if (forced != null) return forced;
        }
        return _json(200, {'message': 'Video deleted'});
      }
      if (method == 'PUT' || method == 'PATCH') {
        return _json(200, {'car': _sampleCar(id), 'message': 'updated'});
      }
      if (method == 'DELETE') {
        return _json(200, {'message': 'deleted'});
      }
      if (segments.length > 1 && segments[1] == 'mark-sold' && method == 'POST') {
        return _json(200, {
          'message': 'Listing marked as sold',
          'car': {..._sampleCar(id), 'status': 'sold'},
        });
      }
      if (segments.length > 1 && segments[1] == 'mark-active' && method == 'POST') {
        return _json(200, {
          'message': 'Listing marked as available',
          'car': {..._sampleCar(id), 'status': 'active'},
        });
      }
      if (segments.length > 1 && segments[1] == 'report' && method == 'POST') {
        return _json(201, {'message': 'Report submitted. Thank you.'});
      }
      if (segments.length > 1 && segments[1] == 'contact' && method == 'GET') {
        final override = carContactOverrides[id];
        if (override != null) {
          return override();
        }
        // Default: a genuine, error-free "no contact phone" response.
        return _json(200, {
          'contact_phone': null,
          'contact_phones': <dynamic>[],
          'has_contact_phone': false,
        });
      }
      if (method == 'GET' && segments.length == 1) {
        carDetailFetchCount++;
        final override = carDetailOverrides[id];
        if (override != null) {
          return override();
        }
      }
      return _json(200, {'car': _sampleCar(id)});
    }

    if (path == '/api/users/blocked') {
      return _json(200, {'blocked_users': <dynamic>[]});
    }

    // OOM-fix follow-up regression coverage: POST /api/process-car-images
    // (Sell photo prestage's enqueue endpoint) and GET /api/jobs/<job_id>
    // (the shared job-status poll endpoint).
    if (path == '/api/process-car-images' && method == 'POST') {
      final isAsync = (request.url.queryParameters['async'] ?? '') == '1';
      final skipBlur = (request.url.queryParameters['skip_blur'] ?? '') == '1';
      final fileCount = _countMultipartParts(request, 'images');
      processCarImagesCalls.add({
        'async': isAsync,
        'skip_blur': skipBlur,
        'file_count': fileCount,
      });
      final override = processCarImagesOverride;
      if (override != null) {
        final forced = override(request);
        if (forced != null) return forced;
      }
      if (fileCount == 0) {
        return _json(400, {'error': 'No image files provided'});
      }
      if (isAsync) {
        final batchSeq = _processCarImagesJobIdSeq;
        _processCarImagesJobIdSeq++;
        final jobIds = List<String>.generate(
          fileCount,
          (i) => 'job-$batchSeq-$i',
        );
        for (final id in jobIds) {
          jobStatusQueue.putIfAbsent(
            id,
            () => [
              {
                'state': 'SUCCESS',
                'result': {'rel_path': 'uploads/car_photos/staged_$id.jpg'},
              },
            ],
          );
        }
        return _json(202, {'success': true, 'job_ids': jobIds});
      }
      // Synchronous (legacy) branch -- OOM-fix regression guard: production
      // Sell prestage must never hit this branch; kept only so a test can
      // assert that explicitly via [processCarImagesCalls].
      return _json(200, {
        'processed_images': List<String>.generate(
          fileCount,
          (i) => 'uploads/car_photos/sync_$i.jpg',
        ),
        'processed_images_base64': <String>[],
      });
    }

    if (path.startsWith('/api/jobs/') && method == 'GET') {
      final jobId = Uri.decodeComponent(path.substring('/api/jobs/'.length));
      jobStatusPollCalls.add(jobId);
      final queue = jobStatusQueue[jobId];
      if (queue == null || queue.isEmpty) {
        return _json(404, {'error': 'job_not_found'});
      }
      final next = queue.length > 1 ? queue.removeAt(0) : queue.first;
      return _json(200, next);
    }

    // B-07/B-04 regression coverage.
    if (path == '/api/user/notifications' && method == 'GET') {
      final override = notificationsGetOverride;
      if (override != null) {
        return override();
      }
      final list = notificationsOverride ?? const <Map<String, dynamic>>[];
      return _json(200, {
        'notifications': list,
        'pagination': {'has_next': false},
      });
    }
    if (path.startsWith('/api/user/notifications/') &&
        path.endsWith('/read') &&
        method == 'PATCH') {
      final id = Uri.decodeComponent(
        path.substring(
          '/api/user/notifications/'.length,
          path.length - '/read'.length,
        ),
      );
      markNotificationReadCalls.add(id);
      return _json(200, {'message': 'Notification marked read'});
    }

    if (path.startsWith('/api/users/') && path.length > '/api/users/'.length) {
      if (path.endsWith('/block') && method == 'POST') {
        return _json(201, {'message': 'User blocked'});
      }
      if (path.endsWith('/unblock') && method == 'POST') {
        return _json(200, {'message': 'User unblocked'});
      }
      if (path.endsWith('/report') && method == 'POST') {
        return _json(201, {'message': 'Report submitted. Thank you.'});
      }
    }

    if (path.startsWith('/api/dealers/') && path.length > '/api/dealers/'.length) {
      final id = path.substring('/api/dealers/'.length).split('/').first;
      return _json(200, {
        'dealer': {
          'public_id': id,
          'dealership_name': 'Test Dealer',
          'dealership_location': 'Erbil',
          'dealership_socials': {
            'facebook': 'https://www.facebook.com/testdealer',
            'instagram': 'https://www.instagram.com/testdealer',
            'tiktok': 'https://www.tiktok.com/@testdealer',
          },
        },
        'listings': <dynamic>[],
        'stats': {'total_listings': 0, 'featured_listings': 0},
      });
    }

    if (path.startsWith('/api/chat/')) {
      if (path.endsWith('/messages') && method == 'GET') {
        final all = chatMessagesAllItems;
        if (all != null) {
          final perPage =
              int.tryParse(request.url.queryParameters['per_page'] ?? '') ??
                  50;
          final beforeRaw = request.url.queryParameters['before'] ?? '';
          chatMessagesRequestedBefore.add(beforeRaw);

          List<Map<String, dynamic>> eligible = all;
          if (beforeRaw.isNotEmpty) {
            final beforeDt = DateTime.parse(beforeRaw);
            eligible = all
                .where(
                  (m) => DateTime.parse(
                    m['created_at'] as String,
                  ).isBefore(beforeDt),
                )
                .toList();
          }
          // Newest-first slice of `perPage`, then reversed to ascending --
          // mirrors kk/routes/chat.py::get_messages exactly.
          final descSlice = eligible.reversed.take(perPage).toList();
          final page = descSlice.reversed.toList();
          final hasMore = page.isNotEmpty &&
              eligible.any(
                (m) => DateTime.parse(m['created_at'] as String).isBefore(
                  DateTime.parse(page.first['created_at'] as String),
                ),
              );
          return _json(200, {
            'messages': page,
            'per_page': perPage,
            'total': all.length,
            'has_more': hasMore,
          });
        }
        return _json(200, <dynamic>[]);
      }
      if (path.contains('/send') && method == 'POST') {
        // BE-18: record whatever Idempotency-Key header this request carried
        // (case as sent by ApiService — no normalization applied here).
        chatSendIdempotencyKeys.add(
          request.headers['Idempotency-Key'] ??
              request.headers['idempotency-key'],
        );
        // F-11: let a test force a specific status/throw for this call.
        final override = chatSendOverride;
        final callIndex = chatSendCallCount;
        chatSendCallCount++;
        if (override != null) {
          final forced = override(request, callIndex);
          if (forced != null) return forced;
        }
        var content = 'stub';
        try {
          if (request.body.isNotEmpty) {
            final decoded = json.decode(request.body);
            if (decoded is Map && decoded['content'] != null) {
              content = decoded['content'].toString();
            }
          }
        } catch (_) {}
        final conversationId = path
            .substring('/api/chat/'.length)
            .split('/')
            .first;
        return _json(201, {
          'success': true,
          'message': {
            'id': 'msg_stub_1',
            'sender_id': '1',
            'receiver_id': 'buyer_1',
            'car_id': conversationId,
            'content': content,
            'message_type': 'text',
            'is_read': false,
            'created_at': '2026-01-01T12:00:00.000Z',
          },
        });
      }
      return _json(200, <String, dynamic>{});
    }

    // CarNet V1 batch 2 (favorites pagination) regression coverage:
    // GET /api/user/favorites?page=N&per_page=M, paginated from
    // [favoritesAllItems] when set (falls through to the generic empty-list
    // stub in the switch below otherwise).
    if (path == '/api/user/favorites' && method == 'GET') {
      final all = favoritesAllItems;
      if (all != null) {
        final page = int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
        final perPage =
            int.tryParse(request.url.queryParameters['per_page'] ?? '') ?? 20;
        favoritesRequestedPages.add(page);
        final start = (page - 1) * perPage;
        final items = start >= all.length
            ? <Map<String, dynamic>>[]
            : all.sublist(start, (start + perPage).clamp(0, all.length));
        final hasNext = (start + perPage) < all.length;
        return _json(200, {
          'cars': items,
          'pagination': {
            'page': page,
            'per_page': perPage,
            'has_next': hasNext,
          },
        });
      }
    }

    if (path.startsWith('/api/saved-searches/')) {
      if (method == 'DELETE') {
        return _json(200, {'message': 'deleted'});
      }
      if (method == 'PUT') {
        return _json(200, {
          'saved_search': {
            'id': path.substring('/api/saved-searches/'.length).split('/').first,
            'name': 'Updated search',
            'filters': {'brand': 'toyota'},
            'notify': true,
          },
        });
      }
    }

    if (path.startsWith('/api/analytics/')) {
      return _json(200, <String, dynamic>{});
    }

    switch (path) {
      case '/api/analytics/listings':
        return _json(200, <dynamic>[]);
      case '/api/my_listings':
        return _json(200, <dynamic>[]);
      case '/api/user/my-listings':
        final byStatus = myListingsByStatus;
        if (byStatus != null) {
          final status = request.url.queryParameters['status'] ?? '';
          final items = byStatus[status] ?? const <Map<String, dynamic>>[];
          return _json(200, {
            'cars': items,
            'pagination': {'has_next': false},
          });
        }
        return _json(200, {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        });
      case '/api/cars':
        if (method == 'POST') {
          return _json(201, {
            'message': 'Car listing created successfully',
            'car': _sampleCar('mock_car_new'),
          });
        }
        return _json(200, {
          'cars': <dynamic>[_sampleCar('list_car_1')],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        });
      case '/api/chats':
        return _json(200, _sampleChats());
      case '/api/chat/unread_count':
        return _json(200, {'unread_count': 0});
      case '/api/auth/phone/verify':
        if (phoneVerifyOverride != null) return phoneVerifyOverride!();
        return _json(200, {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
          'user': {'id': 1, 'username': 'test', 'is_admin': false},
        });
      case '/api/auth/login':
      case '/api/auth/signup':
        return _json(200, {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
          'user': {'id': 1, 'username': 'test', 'is_admin': false},
        });
      case '/api/auth/phone/start':
        var createIfMissing = true;
        var purpose = '';
        try {
          if (request.body.isNotEmpty) {
            final decoded = json.decode(request.body);
            if (decoded is Map) {
              if (decoded.containsKey('create_if_missing')) {
                createIfMissing = decoded['create_if_missing'] == true;
              }
              purpose = (decoded['purpose'] ?? '').toString().trim().toLowerCase();
            }
          }
        } catch (_) {}
        if (!createIfMissing) {
          if (purpose == 'dealer') {
            return _json(409, {
              'message':
                  'This phone number is registered to a personal account. Please use personal login.',
              'code': 'personal_account_exists',
            });
          }
          return _json(404, {
            'message':
                'No account found with this phone number. Please sign up first.',
            'code': 'account_not_found',
          });
        }
        return _json(200, {
          'sent': true,
          'message': 'Verification code sent',
          'dev_code': '123456',
        });
      case '/api/auth/forgot-password':
        return _json(200, {
          'message': 'If the account exists, a reset code has been sent',
        });
      case '/api/auth/reset-password':
        return _json(200, {'message': 'Password reset successful'});
      case '/api/auth/verify-email':
        return _json(200, {'message': 'Email verified successfully'});
      case '/api/auth/change-password':
        return _json(200, {'message': 'Password changed successfully'});
      case '/api/auth/me':
        final authFail = _authGuard(request);
        if (authFail != null) return authFail;
        return _json(200, {
          'id': 1,
          'username': 'testuser',
          'phone_number': '+9647701234567',
          'email': 'test@example.com',
          'is_admin': false,
          'account_type': 'individual',
          'first_name': 'Test',
          'last_name': 'User',
        });
      case '/api/user/profile':
        if (method == 'PUT') {
          // Echo back whichever profile fields the caller actually sent
          // (e.g. `phone_number`, `email`) so tests that drive a real
          // send-code -> verify UI flow (fix 3: account phone-number
          // change) can assert the change was actually applied, not just
          // that *some* fixed stub user came back.
          Map<String, dynamic> sent = const {};
          if (request.body.isNotEmpty) {
            final decoded = json.decode(request.body);
            if (decoded is Map<String, dynamic>) sent = decoded;
          }
          final user = {
            'id': 1,
            'username': 'test',
            'first_name': 'Updated',
            'last_name': 'User',
            'is_admin': false,
            'account_type': 'individual',
            if (sent['phone_number'] != null)
              'phone_number': sent['phone_number'],
            if (sent['email'] != null) 'email': sent['email'],
          };
          if (sent.containsKey('first_name')) {
            user['first_name'] = sent['first_name'];
          }
          if (sent.containsKey('last_name')) {
            user['last_name'] = sent['last_name'];
          }
          return _json(200, {
            'message': 'Profile updated successfully',
            'user': user,
          });
        }
        return _json(200, {
          'user': {
            'id': 1,
            'username': 'test',
            'is_admin': false,
            'account_type': 'individual',
          },
        });
      case '/api/user/favorites':
      case '/api/user/recently-viewed':
        return _json(200, {
          'cars': <dynamic>[],
          'pagination': {'has_next': false},
        });
      case '/api/user/dealer-profile':
        return _json(200, {
          'dealer': {
            'dealership_name': 'Test Dealer',
            'dealership_location': 'Erbil',
          },
        });
      case '/api/saved-searches/sync':
        if (emptySavedSearches) {
          return _json(200, {'saved_searches': <dynamic>[]});
        }
        return _json(200, {
          'saved_searches': [
            {
              'id': '550e8400-e29b-41d4-a716-446655440000',
              'name': 'Camry deals',
              'filters': {'brand': 'toyota', 'model': 'camry'},
              'notify': true,
              'created_at': '2026-01-01T12:00:00.000Z',
            },
          ],
        });
      case '/api/saved-searches':
        if (method == 'POST') {
          return _json(201, {
            'saved_search': {
              'id': '550e8400-e29b-41d4-a716-446655440000',
              'name': 'Mock search',
              'filters': {'brand': 'toyota'},
              'notify': true,
            },
          });
        }
        if (emptySavedSearches) {
          return _json(200, {'saved_searches': <dynamic>[]});
        }
        return _json(200, {
          'saved_searches': [
            {
              'id': '550e8400-e29b-41d4-a716-446655440000',
              'name': 'Camry deals',
              'filters': {'brand': 'toyota', 'model': 'camry'},
              'notify': true,
              'created_at': '2026-01-01T12:00:00.000Z',
            },
          ],
        });
      case '/api/auth/send_otp':
        return _json(200, {'sent': false, 'message': 'stub'});
      case '/api/auth/delete-account':
        return _json(200, {'message': 'Account deleted successfully'});
      case '/api/auth/refresh':
        return _json(200, {
          'access_token': 'test_access_token',
          'refresh_token': 'test_refresh_token',
        });
      case '/api/config/trust':
        return _json(200, {
          'support_email': 'support@test.example',
          'privacy_url': 'https://example.com/privacy',
          'terms_url': 'https://example.com/terms',
        });
      case '/api/config/app':
        return _json(200, {
          'min_app_version': '',
          'min_android_build': null,
          'min_ios_build': null,
          'force_update_message': 'Please update CarNet to continue.',
          'recommended_app_version': '',
          'recommended_android_build': null,
          'recommended_ios_build': null,
          'soft_update_message': 'A newer version of CarNet is available.',
          'android_store_url':
              'https://play.google.com/store/apps/details?id=com.carnetiq.app',
          'ios_store_url': '',
          'listing_require_approval': false,
          'feature_flags': {
            'sell': true,
            'chat': true,
            'dealers': true,
            'comparison': true,
            'saved_searches': true,
          },
        });
      case '/api/push/preferences':
        return _json(200, {'push_enabled': true});
      case '/api/dealers':
        return _json(200, {
          'dealers': <dynamic>[],
          'pagination': {'has_next': false, 'page': 1, 'per_page': 20},
        });
      default:
        return _json(200, <String, dynamic>{});
    }
  }
}
